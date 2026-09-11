-- Open in Sheets — hands a CSV to ~/bin/csv2sheet, which uploads it to Google
-- Drive as a real Sheet and opens it in your Mac's default browser.
--
-- accountLabel is rewritten by install.sh when it builds a per-account droplet
-- ("Open in Sheets (Work).app" and so on). Left empty, the droplet asks which
-- account to use whenever more than one is configured.

property accountLabel : ""

on processFile(f)
	set p to POSIX path of f
	set cmd to "$HOME/bin/csv2sheet"
	if accountLabel is not "" then
		set cmd to cmd & " --account " & quoted form of accountLabel
	end if
	do shell script cmd & " " & quoted form of p
end processFile

on open theFiles
	repeat with f in theFiles
		my processFile(f)
	end repeat
end open

on run
	set theFile to choose file with prompt "Choose a CSV to open in Google Sheets:"
	my processFile(theFile)
end run
