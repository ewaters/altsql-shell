= Desired Features

 * If table output vastly overextends the terminal width, we should use multi-line output to keep the table informative
   - or, allow a horizontal scrolling pager

 * Parse .my.cnf and support options there-in
   - prompt = \\u@\\h[\\R:\\m:\\s]>
   - safe-updates
   - select_limit
   - skip-auto-rehash
   - database
   - host
   - user
   - password

 * Show the header ocassionally if we're many pages into the output
   That way, you don't have to scroll to the top to know which column is which

 * Have some visual way of seeing the width of the data in each column.  In large tables, it's unclear if the data is an empty string ('') or some whitespace.

= Outstanding issues

 * Support \c at end to abandon statement
 * ; or \G contained inside a quote block but ending a line
 * Ctrl-A to go to beginning of line turns Backspace into a forward delete (WTF?)
 * Enter key on an empty line shouldn't go to a new line
 * Show the context of the error:

   altsqlc> show tables limit 100;
   Error at pos 17, line 1

 * If MySQL server has gone away, it doesn't communicate that it reconnects

