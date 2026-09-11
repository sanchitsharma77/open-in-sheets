-- Open in Sheets — hands a CSV to ~/bin/csv2sheet, which uploads it to Google
-- Drive as a real Sheet and opens it in Chrome.

on processFile(f)
	set p to POSIX path of f
	do shell script "$HOME/bin/csv2sheet " & quoted form of p
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
