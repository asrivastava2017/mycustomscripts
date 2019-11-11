$line = 0; Get-Content .\xyz.txt | Select-Object -Last ((Get-Content .\xyz.txt | Measure-Object ).Count - $line) | Select-Object -First 1
(Get-Content C:\Web.dev).replace('user_id_of_db', 'hua-ya-nahi') | Set-Content C:\Web.dev
