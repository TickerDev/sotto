import Foundation

enum MailDraftScript {
    static let source = AppleMailScript.helpers + "\n" + #"""
on snapshot(m)
    tell application id "com.apple.mail"
        set row to current application's NSMutableDictionary's dictionary()
        row's setObject:(id of m) forKey:"native_id"
        row's setObject:(extract address from (sender of m)) forKey:"sender"
        row's setObject:(subject of m) forKey:"subject"
        row's setObject:((content of m) as text) forKey:"body"
        row's setObject:(address of every to recipient of m) forKey:"to"
        row's setObject:(count of cc recipients of m) forKey:"cc_count"
        row's setObject:(count of bcc recipients of m) forKey:"bcc_count"
        row's setObject:(visible of m) forKey:"visible"
    end tell
    return row
end snapshot
on run
    set d to current application's NSFileHandle's fileHandleWithStandardInput()'s readDataToEndOfFile()
    set args to current application's NSJSONSerialization's JSONObjectWithData:d options:0 |error|:(missing value)
    if args is missing value then error "Invalid draft request"
    set op to (args's objectForKey:"action") as text
    tell application id "com.apple.mail"
        if op is "create" then
            set aid to (args's objectForKey:"account_id") as text
            set candidates to accounts whose id is aid
            if (count of candidates) is not 1 then error "Sender account changed"
            set a to item 1 of candidates
            if not enabled of a then error "Sender account disabled"
            set fromAddress to (args's objectForKey:"sender") as text
            ignoring case
                if (email addresses of a) does not contain fromAddress then error "Sender address changed"
            end ignoring
            set titleText to (args's objectForKey:"subject") as text
            set bodyText to (args's objectForKey:"body") as text
            set m to make new outgoing message with properties {sender:fromAddress, subject:titleText, content:bodyText, visible:false}
            set message signature of m to missing value
            set content of m to bodyText
            set targets to (args's objectForKey:"to") as list
            repeat with targetAddress in targets
                make new to recipient at end of to recipients of m with properties {address:(targetAddress as text)}
            end repeat
            set visible of m to true
            set row to current application's NSMutableDictionary's dictionary()
            row's setObject:(id of m) forKey:"native_id"
            return my emitJSON(row)
        end if
        if op is "read" then
            set mid to (args's objectForKey:"native_id") as integer
            set candidates to outgoing messages whose id is mid
            if (count of candidates) is not 1 then error "Compose window no longer exists"
            return my emitJSON(my snapshot(item 1 of candidates))
        end if
    end tell
    error "Unsupported draft operation"
end run
"""#
}
