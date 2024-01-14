@echo off

set _LOG_DIR=C:\_work\quic\dpapi
set _PRETRACE_LOG_DIR=%_LOG_DIR%\PreTraceLogs
set _SCRIPT_PATH=%~dp0%
set _NGC_TRACES_TMP=%_LOG_DIR%\NGC_trace.txt
set _BIO_TRACES_TMP=%_LOG_DIR%\BIO_trace.txt
set _KERB_TRACES_TMP=%_LOG_DIR%\KERB_trace.txt
set _WEB_AUTH_TRACES_TMP=%_LOG_DIR%\WEBAUTH_trace.txt

IF EXIST %_LOG_DIR% ( rd /s /q %_LOG_DIR% )
IF EXIST %_PRETRACE_LOG_DIR% ( rd /s /q %_PRETRACE_LOG_DIR% )
md %_LOG_DIR%
md %_PRETRACE_LOG_DIR%

REM ** NGC TRACES **
(
	echo {B66B577F-AE49-5CCF-D2D7-8EB96BFD440C} 0x0
	echo {CAC8D861-7B16-5B6B-5FC0-85014776BDAC} 0x0
	echo {6D7051A0-9C83-5E52-CF8F-0ECAF5D5F6FD} 0x0
	echo {0ABA6892-455B-551D-7DA8-3A8F85225E1A} 0x0
	echo {9DF6A82D-5174-5EBF-842A-39947C48BF2A} 0x0
	echo {9B223F67-67A1-5B53-9126-4593FE81DF25} 0x0
	echo {89F392FF-EE7C-56A3-3F61-2D5B31A36935} 0x0
	echo {CDD94AC7-CD2F-5189-E126-2DEB1B2FACBF} 0x0
	echo {2056054C-97A6-5AE4-B181-38BC6B58007E} 0x0
	echo {786396CD-2FF3-53D3-D1CA-43E41D9FB73B} 0x0
	echo {1D6540CE-A81B-4E74-AD35-EEF8463F97F5} 0xffff
	echo {3A8D6942-B034-48e2-B314-F69C2B4655A3} 0xffffffff
	echo {D5A5B540-C580-4DEE-8BB4-185E34AA00C5} 0x0
	echo {7955d36a-450b-5e2a-a079-95876bca450a} 0x0
	echo {c3feb5bf-1a8d-53f3-aaa8-44496392bf69} 0x0
	echo {78983c7d-917f-58da-e8d4-f393decf4ec0} 0x0
	echo {36FF4C84-82A2-4B23-8BA5-A25CBDFF3410} 0x0
	echo {5bbca4a8-b209-48dc-a8c7-b23d3e5216fb} 0x00FFFFFF
	echo {9D4CA978-8A14-545E-C047-A45991F0E92F} 0x0
	echo {73370BD6-85E5-430B-B60A-FEA1285808A7} 0x0
	echo {F0DB7EF8-B6F3-4005-9937-FEB77B9E1B43} 0x0
	echo {54164045-7C50-4905-963F-E5BC1EEF0CCA} 0x0
	echo {89A2278B-C662-4AFF-A06C-46AD3F220BCA} 0x0
	echo {BC0669E1-A10D-4A78-834E-1CA3C806C93B} 0x0
	echo {BEA18B89-126F-4155-9EE4-D36038B02680} 0x0
	echo {B2D1F576-2E85-4489-B504-1861C40544B3} 0x0
	echo {98BF1CD3-583E-4926-95EE-A61BF3F46470} 0x0
	echo {AF9CC194-E9A8-42BD-B0D1-834E9CFAB799} 0x0
	echo {d0034f5e-3686-5a74-dc48-5a22dd4f3d5b} 0x0
	echo {aa02d1a4-72d8-5f50-d425-7402ea09253a} 0x0
	echo {9FBF7B95-0697-4935-ADA2-887BE9DF12BC} 0x0
	echo {3DA494E4-0FE2-415C-B895-FB5265C5C83B} 0x0
	echo {8db3086d-116f-5bed-cfd5-9afda80d28ea} 0x0
) >%_NGC_TRACES_TMP%

REM ** Bio Traces **
(
	echo {34BEC984-F11F-4F1F-BB9B-3BA33C8D0132} 0xffff
	echo {225b3fed-0356-59d1-1f82-eed163299fa8} 0x0
	echo {9dadd79b-d556-53f2-67c4-129fa62b7512} 0x0
	echo {1B5106B1-7622-4740-AD81-D9C6EE74F124} 0x0
	echo {1d480c11-3870-4b19-9144-47a53cd973bd} 0x0
	echo {39A5AA08-031D-4777-A32D-ED386BF03470} 0x0
) >%_BIO_TRACES_TMP%

REM ** Kerb Traces **
(
	echo {D0B639E0-E650-4D1D-8F39-1580ADE72784} 0x40141F
	echo {169EC169-5B77-4A3E-9DB6-441799D5CACB} 0xffffff
	echo {DAA76F6A-2D11-4399-A646-1D62B7380F15} 0xffffff
	echo {366B218A-A5AA-4096-8131-0BDAFCC90E93} 0xffffffff
	echo {4D9DFB91-4337-465A-A8B5-05A27D930D48} 0x0
	echo {AC69AE5B-5B21-405F-8266-4424944A43E9} 0xffffffff
	echo {5BBB6C18-AA45-49b1-A15F-085F7ED0AA90} 0x15003
	echo {60A7AB7A-BC57-43E9-B78A-A1D516577AE3} 0xffffff
	echo {FACB33C4-4513-4C38-AD1E-57C1F6828FC0} 0xffffffff
	echo {6B510852-3583-4e2d-AFFE-A67F9F223438} 0x201207
	echo {1BBA8B19-7F31-43c0-9643-6E911F79A06B} 0x23083
	echo {97A38277-13C0-4394-A0B2-2A70B465D64F} 0xff
	echo {EC3CA551-21E9-47D0-9742-1195429831BB} 0xfff
	echo {5AF52B0D-E633-4ead-828A-4B85B8DAAC2B} 0xFFFF
	echo {CA030134-54CD-4130-9177-DAE76A3C5791} 0xfffffff
	echo {2A6FAF47-5449-4805-89A3-A504F3E221A6} 0xFFFF
	echo {4DE9BC9C-B27A-43C9-8994-0915F1A5E24F} 0xffffff
) >%_KERB_TRACES_TMP%

REM ** Web Auth Traces **
(
	echo {37D2C3CD-C5D4-4587-8531-4696C44244C8} 0x0000FDFF
	echo {FB6A424F-B5D6-4329-B9B5-A975B3A93EAD} 0x000003FF
	echo {6165F3E2-AE38-45D4-9B23-6B4818758BD9} 0x0000FFFF
	echo {EA3F84FC-03BB-540e-B6AA-9664F81A31FB} 0xFFFF
	echo {133A980D-035D-4E2D-B250-94577AD8FCED} 0xFFFFFFFF
	echo {7FDD167C-79E5-4403-8C84-B7C0BB9923A1} 0xFFF
	echo {A74EFE00-14BE-4ef9-9DA9-1484D5473302} 0xFFFFFFFF
	echo {A74EFE00-14BE-4ef9-9DA9-1484D5473301} 0xFFFFFFFF
	echo {A74EFE00-14BE-4ef9-9DA9-1484D5473305} 0xFFFFFFFF
	echo {2A3C6602-411E-4DC6-B138-EA19D64F5BBA} 0xFFFF
	echo {EF98103D-8D3A-4BEF-9DF2-2156563E64FA} 0xFFFF
	echo {B3A7698A-0C45-44DA-B73D-E181C9B5C8E6} 0x7FFFFF
	echo {4E749B6A-667D-4c72-80EF-373EE3246B08} 0x7FFFFF
	echo {20F61733-57F1-4127-9F48-4AB7A9308AE2} 0xFFFFFFFF
	echo {D93FE84A-795E-4608-80EC-CE29A96C8658} 0x7FFFFFFF
	echo {3F8B9EF5-BBD2-4C81-B6C9-DA3CDB72D3C5} 0x7
	echo {B1108F75-3252-4b66-9239-80FD47E06494} 0x2FF
	echo {C10B942D-AE1B-4786-BC66-052E5B4BE40E} 0x3FF
	echo {82c7d3df-434d-44fc-a7cc-453a8075144e} 0x2FF
) >%_WEB_AUTH_TRACES_TMP%

reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v BuildLabEx > %_LOG_DIR%\build.txt

REM **NGC**
logman create trace NgcTraceAll -pf %_NGC_TRACES_TMP% -ft 1:00 -rt -o %_LOG_DIR%\ngctraceall.etl -ets
certutil -setreg -f Enroll\Debug 0xffffffe3
certutil -setreg ngc\Debug 1

REM **Biometrics**
wevtutil.exe set-log "Microsoft-Windows-Biometrics/Operational" /enabled:false
wevtutil.exe export-log "Microsoft-Windows-Biometrics/Operational" %_PRETRACE_LOG_DIR%\winbio_oper.evtx /overwrite:true
wevtutil.exe set-log "Microsoft-Windows-Biometrics/Operational" /enabled:true /rt:false /q:true

REM sc query wbiosrvc | findstr /is RUNNING
REM if %errorlevel% EQU 0 (net stop wbiosrvc)

logman create trace BioTraceAll -pf %_BIO_TRACES_TMP% -ft 1:00 -rt -o %_LOG_DIR%\biotraceall.etl -ets

REM **KERB**
wevtutil.exe set-log "Microsoft-Windows-Kerberos/Operational" /enabled:true /rt:false /q:true

logman start KerbTraceAll -pf %_KERB_TRACES_TMP% -o %_LOG_DIR%\kerbtraceall.etl -ets

REM **AAD**
wevtutil.exe set-log "Microsoft-Windows-AAD/Analytic" /enabled:true /rt:false /q:true

wevtutil.exe set-log "Microsoft-Windows-AAD/Operational" /enabled:false
wevtutil.exe export-log "Microsoft-Windows-AAD/Operational" %_PRETRACE_LOG_DIR%\aad_oper.evtx /ow:true
wevtutil.exe set-log "Microsoft-Windows-AAD/Operational"  /enabled:true /rt:false /q:true

wevtutil.exe set-log "Microsoft-Windows-User Device Registration/Debug" /enabled:true /rt:false /q:true

dsregcmd /status /debug /all > %_PRETRACE_LOG_DIR%\dsregcmddebug.txt

REM **Pregen Pool**
certutil -setreg ngc\Debug 1

REM **WEB AUTH**
nltest /dbflag:0x2000FFFF
logman start WebAuthTraceAll -pf %_WEB_AUTH_TRACES_TMP% -o %_LOG_DIR%\webauthtraceall.etl -ets

echo **Tracing start**

:cleanup

echo ...
