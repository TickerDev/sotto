import Foundation

/// Reviewed source only. Queries and message identifiers arrive as private JSON
/// over stdin; no user text is evaluated, rendered, or included in process args.
enum AppleMailScript {
    static let helpers = #"""
use framework "Foundation"
use scripting additions
on jsonData(value)
    set d to current application's NSJSONSerialization's dataWithJSONObject:value options:0 |error|:(missing value)
    if d is missing value then error "Mail returned invalid structured data"
    return d
end jsonData
on emitJSON(value)
    set d to my jsonData(value)
    if (d's |length|() as integer) > 60000 then error "Mail output exceeds its safe limit"
    return (current application's NSString's alloc()'s initWithData:d encoding:(current application's NSUTF8StringEncoding)) as text
end emitJSON
on byteSize(value)
    return ((current application's NSString's stringWithString:value)'s lengthOfBytesUsingEncoding:(current application's NSUTF8StringEncoding)) as integer
end byteSize
on isoDate(value)
    set f to current application's NSISO8601DateFormatter's alloc()'s init()
    return (f's stringFromDate:value) as text
end isoDate
on scriptDate(value)
    set f to current application's NSISO8601DateFormatter's alloc()'s init()
    set d to f's dateFromString:value
    if d is missing value then error "Invalid Mail date"
    return d as date
end scriptDate
on excerpt(value)
    set d to (current application's NSString's stringWithString:value)'s dataUsingEncoding:(current application's NSUTF8StringEncoding)
    set n to (d's |length|()) as integer
    if n ≤ 16000 then return value
    set n to 16000
    repeat 4 times
        set part to d's subdataWithRange:{location:0, |length|:n}
        set s to current application's NSString's alloc()'s initWithData:part encoding:(current application's NSUTF8StringEncoding)
        if s is not missing value then return s as text
        set n to n - 1
    end repeat
    error "Mail text could not be safely decoded"
end excerpt
"""#
    static let source = helpers + "\n" + #"""
on messageRow(m)
    tell application id "com.apple.mail"
        if deleted status of m or junk mail status of m then error "Deleted or junk messages are outside this read scope"
        set mid to id of m
        set rfc to message id of m
        set s to subject of m
        set fromText to sender of m
        set receivedDate to date received of m
        set isRead to read status of m
        set box to mailbox of m
        set boxName to name of box
        set a to account of box
        set aid to id of a
        set accountName to name of a
        if not enabled of a then error "This Mail account is disabled"
    end tell
    if my byteSize(s) > 2000 or my byteSize(fromText) > 2000 or my byteSize(rfc) > 1000 or my byteSize(aid) > 1000 or my byteSize(boxName) > 1000 or my byteSize(accountName) > 1000 then error "Oversized Mail metadata"
    set row to current application's NSMutableDictionary's dictionary()
    row's setObject:mid forKey:"native_id"
    row's setObject:rfc forKey:"rfc_message_id"
    row's setObject:s forKey:"subject"
    row's setObject:fromText forKey:"sender"
    row's setObject:(my isoDate(receivedDate)) forKey:"received_at"
    row's setObject:isRead forKey:"is_read"
    row's setObject:aid forKey:"account_id"
    row's setObject:accountName forKey:"account_name"
    row's setObject:boxName forKey:"mailbox"
    return row
end messageRow
on run
    set d to current application's NSFileHandle's fileHandleWithStandardInput()'s readDataToEndOfFile()
    set args to current application's NSJSONSerialization's JSONObjectWithData:d options:0 |error|:(missing value)
    if args is missing value then error "Invalid Mail request"
    set op to (args's objectForKey:"action") as text
    set result to current application's NSMutableDictionary's dictionary()
    tell application id "com.apple.mail"
        if op is "accounts" then
            set rows to current application's NSMutableArray's array()
            set limited to false
            repeat with a in accounts
                if (rows's |count|() as integer) ≥ 10 then
                    set limited to true
                    exit repeat
                end if
                set aid to id of a
                set accountName to name of a
                set addresses to email addresses of a
                if my byteSize(aid) > 1000 or my byteSize(accountName) > 1000 or (count of addresses) > 10 then error "Oversized Mail account"
                repeat with addressText in addresses
                    if my byteSize(addressText as text) > 1000 then error "Oversized Mail address"
                end repeat
                set row to current application's NSMutableDictionary's dictionary()
                row's setObject:aid forKey:"id"
                row's setObject:accountName forKey:"name"
                row's setObject:(enabled of a) forKey:"enabled"
                row's setObject:addresses forKey:"addresses"
                rows's addObject:row
                if ((my jsonData(rows))'s |length|() as integer) > 50000 then
                    rows's removeLastObject()
                    set limited to true
                    exit repeat
                end if
            end repeat
            result's setObject:rows forKey:"accounts"
            result's setObject:limited forKey:"limited"
            return my emitJSON(result)
        end if
        if op is "search" then
            set query to (args's objectForKey:"query") as text
            set aid to (args's objectForKey:"account_id") as text
            set unreadOnly to (args's objectForKey:"unread_only") as boolean
            set afterText to (args's objectForKey:"after") as text
            set beforeText to (args's objectForKey:"before") as text
            if afterText is not "" then set afterDate to my scriptDate(afterText)
            if beforeText is not "" then set beforeDate to my scriptDate(beforeText)
            set rows to current application's NSMutableArray's array()
            set inspected to 0
            set skipped to 0
            set limited to false
            set scanCount to count of messages of inbox
            if scanCount > 200 then
                set scanCount to 200
                set limited to true
            end if
            repeat with i from 1 to scanCount
                if (rows's |count|() as integer) ≥ 20 then
                    set limited to true
                    exit repeat
                end if
                set inspected to inspected + 1
                try
                    set m to message i of inbox
                    set row to my messageRow(m)
                    set matchesRequest to true
                    if aid is not "" and ((row's objectForKey:"account_id") as text) is not aid then set matchesRequest to false
                    if unreadOnly and ((row's objectForKey:"is_read") as boolean) then set matchesRequest to false
                    set receivedDate to date received of m
                    if afterText is not "" then
                        if receivedDate < afterDate then set matchesRequest to false
                    end if
                    if beforeText is not "" then
                        if receivedDate ≥ beforeDate then set matchesRequest to false
                    end if
                    if query is not "" then
                        set s to (row's objectForKey:"subject") as text
                        set fromText to (row's objectForKey:"sender") as text
                        ignoring case
                            if s does not contain query and fromText does not contain query then set matchesRequest to false
                        end ignoring
                    end if
                    if matchesRequest then
                        rows's addObject:row
                        if ((my jsonData(rows))'s |length|() as integer) > 50000 then
                            rows's removeLastObject()
                            set limited to true
                            exit repeat
                        end if
                    end if
                on error
                    set skipped to skipped + 1
                end try
            end repeat
            result's setObject:rows forKey:"messages"
            result's setObject:limited forKey:"limited"
            result's setObject:inspected forKey:"inspected"
            result's setObject:skipped forKey:"skipped"
            return my emitJSON(result)
        end if
        if op is "read" then
            set mid to (args's objectForKey:"native_id") as integer
            set candidates to messages of inbox whose id is mid
            if (count of candidates) is not 1 then error "The message moved or is no longer uniquely available in the inbox"
            set m to item 1 of candidates
            set row to my messageRow(m)
            repeat with k in {"account_id", "rfc_message_id", "subject", "sender", "received_at", "mailbox"}
                if ((row's objectForKey:k) as text) is not ((args's objectForKey:k) as text) then error "The Mail message changed; search again"
            end repeat
            set messageBytes to message size of m
            if messageBytes < 0 or messageBytes > 2000000 then error "This Mail message exceeds the safe size limit"
            set wasRead to read status of m
            set p to content of m as text
            if my byteSize(p) > 2000000 then error "This Mail body exceeds the safe size limit"
            set bodyText to my excerpt(p)
            set afterRow to my messageRow(m)
            repeat with k in {"account_id", "rfc_message_id", "subject", "sender", "received_at", "mailbox"}
                if ((row's objectForKey:k) as text) is not ((afterRow's objectForKey:k) as text) then error "The Mail message changed while reading; search again"
            end repeat
            row's setObject:bodyText forKey:"text"
            row's setObject:(my byteSize(p) > my byteSize(bodyText)) forKey:"partial"
            row's setObject:(wasRead is not ((afterRow's objectForKey:"is_read") as boolean)) forKey:"read_status_changed"
            row's setObject:(afterRow's objectForKey:"is_read") forKey:"is_read"
            return my emitJSON(row)
        end if
    end tell
    error "Unsupported Mail operation"
end run
"""#
}
