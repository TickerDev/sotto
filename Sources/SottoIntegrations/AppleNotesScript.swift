import Foundation

/// Fixed, reviewed source. All variable data is JSON read from private stdin.
/// Never interpolates note text, queries, HTML or identifiers into AppleScript.
enum AppleNotesScript {
    static let source = #"""
use framework "Foundation"
use scripting additions

on emitJSON(value)
    set d to current application's NSJSONSerialization's dataWithJSONObject:value options:0 |error|:(missing value)
    if d is missing value then error "Notes returned invalid structured data"
    return (current application's NSString's alloc()'s initWithData:d encoding:(current application's NSUTF8StringEncoding)) as text
end emitJSON

on byteSize(value)
    return ((current application's NSString's stringWithString:value)'s lengthOfBytesUsingEncoding:(current application's NSUTF8StringEncoding)) as integer
end byteSize

on snapshot(n)
    tell application id "com.apple.Notes"
        if password protected of n then error "Locked Apple Notes cannot be read by Sotto"
        set t to name of n
        set h to body of n
        set p to plaintext of n
        set nid to id of n
        set sharedFlag to shared of n
        set attachmentsCount to count of attachments of n
        set folderName to name of container of n
    end tell
    if my byteSize(h) > 24000 or my byteSize(p) > 24000 or my byteSize(t) > 1000 or my byteSize(folderName) > 1000 then error "This Apple Note exceeds Sotto's bounded read limit"
    set row to current application's NSMutableDictionary's dictionary()
    row's setObject:nid forKey:"id"
    row's setObject:t forKey:"title"
    row's setObject:h forKey:"html"
    row's setObject:p forKey:"text"
    row's setObject:sharedFlag forKey:"shared"
    row's setObject:attachmentsCount forKey:"attachments"
    row's setObject:folderName forKey:"folder"
    return row
end snapshot

on run
    set inputData to current application's NSFileHandle's fileHandleWithStandardInput()'s readDataToEndOfFile()
    set args to current application's NSJSONSerialization's JSONObjectWithData:inputData options:0 |error|:(missing value)
    if args is missing value then error "Invalid Notes request"
    set op to (args's objectForKey:"action") as text
    set result to current application's NSMutableDictionary's dictionary()
    tell application id "com.apple.Notes"
        if op is "destination" then
            set fid to (args's objectForKey:"folder_id") as text
            if fid is "" then
                set targetFolder to default folder of default account
            else
                set candidates to folders whose id is fid
                if (count of candidates) is not 1 then error "Choose an actual Apple Notes folder"
                set targetFolder to item 1 of candidates
            end if
            if shared of targetFolder then error "Creating notes in shared folders is unsupported"
            result's setObject:(id of targetFolder) forKey:"id"
            result's setObject:(name of targetFolder) forKey:"name"
            return my emitJSON(result)
        end if
        if op is "list" or op is "search" then
            set query to (args's objectForKey:"query") as text
            set rows to current application's NSMutableArray's array()
            set inspected to 0
            set limited to false
            repeat with n in notes
                if inspected ≥ 200 or (rows's |count|() as integer) ≥ 20 then
                    set limited to true
                    exit repeat
                end if
                set inspected to inspected + 1
                set t to name of n
                if my byteSize(t) ≤ 1000 then
                    set matched to (query is "")
                    if not matched then
                        ignoring case
                            set matched to t contains query
                        end ignoring
                    end if
                    if matched then
                        set row to current application's NSMutableDictionary's dictionary()
                        row's setObject:(id of n) forKey:"id"
                        row's setObject:t forKey:"title"
                        row's setObject:(password protected of n) forKey:"locked"
                        row's setObject:(shared of n) forKey:"shared"
                        row's setObject:(name of container of n) forKey:"folder"
                        rows's addObject:row
                    end if
                end if
            end repeat
            result's setObject:rows forKey:"notes"
            result's setObject:limited forKey:"limited"
            return my emitJSON(result)
        end if
        if op is "create" then
            set fid to (args's objectForKey:"folder_id") as text
            set candidates to folders whose id is fid
            if (count of candidates) is not 1 then error "Apple Notes destination changed"
            set f to item 1 of candidates
            if shared of f then error "Shared folder creation is unsupported"
            set h to (args's objectForKey:"html") as text
            set t to (args's objectForKey:"title") as text
            set n to make new note at f with properties {body:h}
            set name of n to t
            return my emitJSON(my snapshot(n))
        end if
        set nid to (args's objectForKey:"id") as text
        set candidates to notes whose id is nid
        if (count of candidates) is not 1 then error "Apple Note no longer exists or is ambiguous"
        set n to item 1 of candidates
        if op is "read" then return my emitJSON(my snapshot(n))
        if op is "update" then
            if password protected of n or shared of n or (count of attachments of n) is not 0 then error "Locked, shared or attachment-bearing notes cannot be changed by Sotto"
            set expected to (args's objectForKey:"expected_html") as text
            if (body of n) is not expected then error "Apple Note changed after review; read it again"
            set expectedTitle to (args's objectForKey:"expected_title") as text
            if name of n is not expectedTitle then error "Apple Note title changed after review"
            set h to (args's objectForKey:"html") as text
            set body of n to h
            return my emitJSON(my snapshot(n))
        end if
    end tell
    error "Unsupported Apple Notes operation"
end run
"""#
}
