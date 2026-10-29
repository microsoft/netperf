# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot 'adapters\GcReceiverTraffic.psm1'
$tokens=$null;$errors=$null
$traffic=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$replyBlock=@($traffic.FindAll({
    param($node)
    $node -is [Management.Automation.Language.ScriptBlockExpressionAst] -and
        $node.Extent.Text.Contains('Route-warmup request mismatch.') -and
        @($node.ScriptBlock.ParamBlock.Parameters).Count -eq 1
},$true))
$cleanupBlock=@($traffic.FindAll({
    param($node)
    $node -is [Management.Automation.Language.ScriptBlockExpressionAst] -and
        $node.Extent.Text.Contains('Required route-warmup cleanup failed.') -and
        @($node.ScriptBlock.ParamBlock.Parameters).Count -eq 1
},$true))
if($replyBlock.Count -ne 1 -or $cleanupBlock.Count -ne 1){throw 'Actual warmup exchange and cleanup must be unique.'}
foreach($case in @('valid','bad-data','bad-owner')){
    $listener=$null;$sender=$null
    try{
        $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
        $listener.Start()
        $sender=[Net.Sockets.TcpClient]::new()
        $sender.Connect([Net.IPAddress]::Loopback,$listener.LocalEndpoint.Port)
        $sender.ReceiveTimeout=5000
        $data=[byte[]]::new(512)
        for($index=0;$index -lt $data.Length;$index++){$data[$index]=[byte]($index%251)}
        if($case -eq 'bad-data'){$data[511]=$data[511] -bxor 1}
        $stream=$sender.GetStream();$stream.Write($data,0,$data.Length)
        $sender.Client.Shutdown([Net.Sockets.SocketShutdown]::Send)
        $global:OwnedManagedGcPeer=@{Warmup=@{Owner=$(if($case -eq 'bad-owner'){'changed'}else{'test-owner'});Listener=$listener}}
        $rejected=$false
        try{$reply=& $replyBlock[0].ScriptBlock.GetScriptBlock() 'test-owner'}catch{
            if($_.Exception.Message -notmatch 'request mismatch|changed ownership'){throw}
            $rejected=$true
        }
        if($rejected -ne ($case -ne 'valid')){throw 'The warmup exchange accepted corrupted bytes or a changed owner.'}
        if(-not $rejected){
            $received=[byte[]]::new(512);$offset=0
            while($offset -lt $received.Length){
                $read=$stream.Read($received,$offset,$received.Length-$offset)
                if($read -eq 0){throw 'Warmup reply ended early.'}
                $offset+=$read
            }
            if(($received-join ',') -ne ($data-join ',') -or $stream.ReadByte() -ne -1 -or
                $reply.connections -ne 1 -or $reply.bytesReceived -ne 512 -or $reply.bytesSent -ne 512){
                throw 'The actual warmup reply did not preserve bytes and EOF.'
            }
        }
    }finally{
        if($null -ne $sender){$sender.Dispose()}
        if($null -ne $listener){$listener.Stop()}
        Remove-Variable -Name OwnedManagedGcPeer -Scope Global
    }
}
foreach($case in @('valid','changed-owner','changed-rule','stop-failure')){
    try{
        $calls=[Collections.Generic.List[string]]::new()
        $listener=[pscustomobject]@{}
        $listener|Add-Member ScriptMethod Stop {$calls.Add('stop');if($case -eq 'stop-failure'){throw 'Synthetic listener stop failure.'}}
        $global:OwnedManagedGcPeer=@{Warmup=@{Owner=$(if($case -eq 'changed-owner'){'changed'}else{'test-owner'})
            Rule=$(if($case -eq 'changed-rule'){'unowned-rule'}else{'NetperfGcWarmup-test-owner'});RuleCreated=$true;Listener=$listener}}
        function Remove-NetFirewallRule {[CmdletBinding()]param($Name)
            if($Name -ne 'NetperfGcWarmup-test-owner'){throw 'Unowned warmup rule removal.'}
            $calls.Add('remove')
        }
        $rejected=$false
        try{& $cleanupBlock[0].ScriptBlock.GetScriptBlock() 'test-owner'}catch{
            if($_.Exception.Message -notmatch 'refusing cleanup|Required route-warmup cleanup failed'){throw}
            $rejected=$true
        }
        if($rejected -ne ($case -ne 'valid') -or
            ($case -in @('changed-owner','changed-rule') -and $calls.Count) -or
            ($case -notin @('changed-owner','changed-rule') -and ($calls-join ',') -ne 'stop,remove')){
            throw 'Warmup cleanup changed ownership or skipped required firewall cleanup after a listener failure.'
        }
    }finally{Remove-Variable -Name OwnedManagedGcPeer -Scope Global}
}
$module=Import-Module $path -Force -PassThru
foreach($cleanupFails in @($false,$true)){
    & $module {
        param($cleanupFails)
        function Invoke-Command {
            [CmdletBinding()]param($Session,$ScriptBlock,$ArgumentList)
            if($ScriptBlock.ToString().Contains('New-NetFirewallRule')){throw 'Synthetic warmup setup failure.'}
            if($cleanupFails){throw 'Synthetic warmup cleanup failure.'}
        }
        $failure=$null
        try{Invoke-GcRouteWarmup -State @{ServerAddress='198.19.240.1';PeerAddress='198.19.240.6';Peer=$null}}catch{$failure=$_.Exception}
        if($null -eq $failure -or -not $failure.Data.Contains('RouteWarmupCleanupVerified') -or
            [bool]$failure.Data['RouteWarmupCleanupVerified'] -eq $cleanupFails -or
            $failure.InnerExceptions.Count -ne $(if($cleanupFails){2}else{1})){
            throw 'A primary or cleanup failure was hidden or reported as verified cleanup.'
        }
    } $cleanupFails
}
Write-Output 'Passed9 actual warmup byte/EOF, ownership and aggregated-cleanup cases; loopback checks are not performance evidence.'
