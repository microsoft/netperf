@echo off

set _LOG_DIR=C:\_work\quic\dpapi
set _NGC_TRACES_TMP=%_LOG_DIR%\NGC_trace.txt
set _BIO_TRACES_TMP=%_LOG_DIR%\BIO_trace.txt
set _KERB_TRACES_TMP=%_LOG_DIR%\KERB_trace.txt
set _WEB_AUTH_TRACES_TMP=%_LOG_DIR%\WEBAUTH_trace.txt

REM **NGC**
logman stop NgcTraceAll -ets

certutil -delreg Enroll\Debug
copy /Y %WINDIR%\CertEnroll.log %_LOG_DIR%\CertEnrollWindir.log
copy /Y %USERPROFILE%\CertEnroll.log %_LOG_DIR%\CertEnrollUserProfile.log
copy /Y %LocalAppData%\CertEnroll.

REM **Biometrics**
logman stop BioTraceAll -ets
wevtutil.exe set-log "Microsoft-Windows-Biometrics/Operational" /enabled:false
wevtutil.exe export-log "Microsoft-Windows-Biometrics/Operational" %_LOG_DIR%\winbio_oper.evtx /overwrite:true
wevtutil.exe set-log "Microsoft-Windows-Biometrics/Operational" /enabled:true /rt:false /q:true

REM **KERB**
logman stop KerbTraceAll -ets

wevtutil.exe set-log "Microsoft-Windows-Kerberos/Operational" /enabled:false
wevtutil.exe epl "Microsoft-Windows-Kerberos/Operational" %_LOG_DIR%\kerb.evtx /overwrite:true

copy /Y %LocalAppData%\CertEnroll.log %_LOG_DIR%\CertEnrollLocalAppData.log
copy /Y %WINDIR%\Ngc*.log %_LOG_DIR%\PregenLog.log

REM **AAD**
wevtutil.exe set-log "Microsoft-Windows-AAD/Analytic" /enabled:false
wevtutil.exe export-log "Microsoft-Windows-AAD/Analytic" %_LOG_DIR%\aad_analytic.evtx /overwrite:true

wevtutil.exe set-log "Microsoft-Windows-AAD/Operational" /enabled:false
wevtutil.exe export-log "Microsoft-Windows-AAD/Operational" %_LOG_DIR%\aad_oper.evtx /overwrite:true
wevtutil.exe set-log "Microsoft-Windows-AAD/Operational"  /enabled:true /rt:false /q:true

wevtutil.exe set-log "Microsoft-Windows-User Device Registration/Debug" /enabled:false
wevtutil.exe export-log "Microsoft-Windows-User Device Registration/Debug" %_LOG_DIR%\usrdevicereg_dbg.evtx /overwrite:true

REM ** Application Log **
wevtutil query-events Application "/q:*[System[Provider[@Name='Microsoft-Windows-CertificateServicesClient-CertEnroll']]]" > %_LOG_DIR%\CertificateServicesClientLog.xml
certutil -policycache CertificateServicesClientLog.xml > %_LOG_DIR%\ReadableClientLog.xml
wevtutil.exe export-log Application %_LOG_DIR%\application.evtx /overwrite:true

reg query HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication /s > %_LOG_DIR%\authentication.txt 2>&1
reg query HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Winbio /s > %_LOG_DIR%\winbio.txt 2>&1
reg query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\WbioSrvc /s > %_LOG_DIR%\wbiosrvc.txt 2>&1
reg query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\EAS\Policies /s > %_LOG_DIR%\eas.txt 2>&1
reg query HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Biometrics /s > %_LOG_DIR%\policies.txt 2>&1
reg query HKEY_CURRENT_USER\SOFTWARE\Microsoft\SCEP /s > %_LOG_DIR%\scep.txt 2>&1
reg query HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\SQMClient /s > %_LOG_DIR%\MachineId.txt 2>&1
reg query HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Policies\PassportForWork /s > %_LOG_DIR%\NgcPolicyIntune.txt 2>&1
reg query HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\PassportForWork /s > %_LOG_DIR%\NgcPolicyGp.txt 2>&1
reg query HKEY_CURRENT_USER\SOFTWARE\Policies\Microsoft\PassportForWork /s >> %_LOG_DIR%\NgcPolicyGp.txt 2>&1

dsregcmd /status > %_LOG_DIR%\dsregcmd.txt 2>&1
dsregcmd /status /debug /all > %_LOG_DIR%\dsregcmddebug.txt

certutil -scinfo -silent > %_LOG_DIR%\scinfo.txt 2>&1

REM **SCCM**
Set _SCCM_LOG_DIR=%SystemRoot%\CCM\Logs
if EXIST %_SCCM_LOG_DIR% ( xcopy /Y %_SCCM_LOG_DIR%\CertEnrollAgent.log %_LOG_DIR%\ && xcopy /Y %_SCCM_LOG_DIR%\StateMessage.log %_LOG_DIR%\ && xcopy /Y %_SCCM_LOG_DIR%\DCMAgent.log %_LOG_DIR%\ && xcopy /Y %_SCCM_LOG_DIR%\CIAgent.log %_LOG_DIR%\)
Set _SCCM_LOG_DIR=%SystemRoot%\CCMSetup\Logs
if EXIST %_SCCM_LOG_DIR% ( xcopy /Y %_SCCM_LOG_DIR%\ccmsetup.log  %_LOG_DIR%\)

REM **MDM**
for /F %%i IN ('wevtutil el') DO (
	for /F "tokens=1,2 delims=/" %%j IN ("%%i") DO (
	   IF "%%j" EQU "Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider" (
	     echo Exporting MDM Diagnostic Log channel %%k ...
	     wevtutil qe %%i /f:text /l:en-us > %_LOG_DIR%\%%j-%%k.txt
	   )
	)
)

REM **Pregen Pool**
if EXIST %windir%\ngc*.log (xcopy /Y %windir%\ngc*.log %_LOG_DIR%\)
certutil -delreg ngc\Debug

REM **WEB AUTH**
logman stop WebAuthTraceAll -ets

REM **Copy logs to the remote share winsect**
FOR /F "TOKENS=2 DELIMS=/ " %%I IN ("%Date%") DO (SET _MONTH=%%I)
FOR /F "TOKENS=3 DELIMS=/ " %%I IN ("%Date%") DO SET _DATE=%%I
FOR /F "TOKENS=1 DELIMS=: " %%I IN ("%Time%") DO SET _HOUR=%%I
FOR /F "TOKENS=2 DELIMS=: " %%I IN ("%Time%") DO SET _MIN=%%I

echo ===============
echo ACTION REQUIRED
echo ===============
echo Please share %_LOG_DIR%\* for analysis
