#Requires AutoHotkey v2.0+
#SingleInstance Force
#Warn

; Restore Points Manager for Windows 11
; Manages system restore points with a clean GUI

; ---------- Logging ----------
global LOG_DEBUG := A_ScriptDir "\debug.log"
global LOG_ERROR := A_ScriptDir "\error.log"

try FileDelete(LOG_DEBUG)
try FileDelete(LOG_ERROR)

LogDebug(msg) {
    ;FileAppend(Format("[{1}] DEBUG: {2}`r`n", A_Now, msg), LOG_DEBUG)
}

LogError(msg) {
    ;FileAppend(Format("[{1}] ERROR: {2}`r`n", A_Now, msg), LOG_ERROR)
    LogDebug("ERROR: " msg)
}

; ---------- Admin Check ----------
CheckAdmin() {
    if (!A_IsAdmin) {
        try {
            Run("*RunAs " '"' A_AhkPath '" "' A_ScriptFullPath '"')
            ExitApp
        } catch as e {
            LogError("Failed to elevate to admin: " e.Message)
            MsgBox("This application requires administrator privileges to manage restore points.", "Admin Rights Required", 16)
            ExitApp
        }
    }
}

; ---------- Global Variables ----------
global guiMain := ""
global lvRestorePoints := ""
global btnCreate := ""
global btnDelete := ""
global btnRefresh := ""
global progressOverlay := ""

; ---------- Main Execution ----------
CheckAdmin()
LogDebug("Application started")

; Create the main GUI
CreateGUI()
RefreshRestorePoints()
guiMain.Show()

LogDebug("GUI displayed")

return

; ---------- GUI Creation ----------
CreateGUI() {
    global guiMain := Gui("-MinimizeBox", "Restore Points Manager")
    
    ; Create system tray menu
    trayMenu := A_TrayMenu
    trayMenu.Delete()  ; Clear default menu
    trayMenu.Add("Reload", (*) => Reload())
    trayMenu.Add("Exit", (*) => ExitApp())
    
    ; ListView for restore points
    global lvRestorePoints := guiMain.Add("ListView", "x10 y0 w700 h330 grid", ["ID", "Creation Time", "Description"])
    lvRestorePoints.ModifyCol(1, 30)   ; ID column
    lvRestorePoints.ModifyCol(2, 160)  ; Creation Time column
    lvRestorePoints.ModifyCol(3, 'AutoHdr')  ; Description column
    
    lvRestorePoints.SetFont("s11" " q5", "Segoe UI")
    
    ; Set up ListView events to enable/disable delete button
    lvRestorePoints.OnEvent("Click", UpdateDeleteButtonState)
    
    ; Buttons
    guiMain.setFont("s10")
    global btnCreate := guiMain.Add("Button", "x10 y340 w100 h30", "➕ Create")
    btnCreate.OnEvent("Click", CreateRestorePoint)
    
    global btnRefresh := guiMain.Add("Button", "x120 y340 w100 h30", "🔃 Refresh")
    btnRefresh.OnEvent("Click", (*) => RefreshRestorePoints())
    
    global btnDelete := guiMain.Add("Button", "x610 y340 w100 h30", "❌ Delete")
    btnDelete.OnEvent("Click", DeleteRestorePoint)
    btnDelete.Enabled := false  ; Disabled by default
    
    guiMain.setFont() ; default
    
    ; Set up event handlers
    guiMain.OnEvent("Close", (*) => ExitApp())
}

; ---------- Selection Handling ----------
UpdateDeleteButtonState(*) {
    ; This function is called on any click within the ListView.
    ; We check if an item is selected and update the delete button's state.
    Sleep(10) ; A small delay helps ensure the control's state is updated before we check it.
    hasSel := lvRestorePoints.GetNext() > 0
    btnDelete.Enabled := hasSel
}

; ---------- Progress Overlay ----------
ShowProgress(message) {
    ; Disable all controls
    btnCreate.Enabled := false
    btnDelete.Enabled := false
    btnRefresh.Enabled := false
    lvRestorePoints.Enabled := false
}

HideProgress() {
    ; Enable all controls
    btnCreate.Enabled := true
    btnRefresh.Enabled := true
    lvRestorePoints.Enabled := true
    
    ; Re-enable delete button if an item is selected
    selected := lvRestorePoints.GetNext(0, "F")
    btnDelete.Enabled := (selected != 0)
}

; ---------- Restore Point Functions ----------
RefreshRestorePoints() {
    LogDebug("Refreshing restore points")
    ShowProgress("Loading restore points...")
    
    ; Clear existing items
    lvRestorePoints.Delete()
    
    try {
        ; Use WMI to get restore points
        wmi := ComObject("WbemScripting.SWbemLocator")
        service := wmi.ConnectServer(".", "root\default")
        service.Security_.ImpersonationLevel := 3
        
        ; Query restore points
        colItems := service.ExecQuery("SELECT * FROM SystemRestore")
        
        items := []
        for item in colItems {
            items.Push([item.SequenceNumber, item.CreationTime, item.Description])
        }

        ; Manual bubble sort (descending) as Array.Sort() was not found.
        n := items.Length
        if (n > 1) {
            Loop n - 1 {
                swapped := false
                Loop n - A_Index {
                    j := A_Index
                    if (items[j][1] < items[j + 1][1]) {
                        temp := items[j]
                        items[j] := items[j + 1]
                        items[j + 1] := temp
                        swapped := true
                    }
                }
                if !swapped
                    break ; If no swaps in a pass, array is sorted
            }
        }

        count := items.Length
        LogDebug("Found " count " restore points")

        for item in items {
            lvRestorePoints.Add(, item[1], FormatTime(item[2]), item[3])
        }
        
        LogDebug("Loaded " count " restore points")
    } catch as e {
        LogError("Failed to load restore points: " e.Message)
        MsgBox("Failed to load restore points: " e.Message, "Error", 16)
    } finally {
        HideProgress()
        ; Update button state after refresh
        UpdateDeleteButtonState()
    }
}

FormatTime(wmiTime) {
    ; Convert WMI time format to readable format
    ; WMI time format: YYYYMMDDHHMMSS.mmmmmm+UUU
    if (wmiTime = "") {
        return ""
    }
    
    try {
        ; Extract date and time parts
        year := SubStr(wmiTime, 1, 4)
        month := SubStr(wmiTime, 5, 2)
        day := SubStr(wmiTime, 7, 2)
        hour := SubStr(wmiTime, 9, 2)
        minute := SubStr(wmiTime, 11, 2)
        second := SubStr(wmiTime, 13, 2)
        
        ; Format as readable date/time
        return year "/" month "/" day " " hour ":" minute ":" second
    } catch as e {
        LogError("Failed to format time: " e.Message)
        return wmiTime
    }
}

; ---------- Create Restore Point Dialog ----------
OpenCreateDialog() {
    ; Create a modal GUI to get the restore point description
    dlg := Gui("-MinimizeBox -MaximizeBox +Owner" guiMain.Hwnd, "Create Restore Point")
    dlg.MarginX := 10
    dlg.MarginY := 10

	dlg.SetFont("s10")
    dlg.Add("Text",, "Enter a description for the new restore point:")
    dlg.SetFont() ; default
    editDesc := dlg.Add("Edit", "w255")
    editDesc.Focus()

    dlgBtnCreate := dlg.Add("Button", "y+m w100 h30 Default", "➕ Create")
    dlgBtnCancel := dlg.Add("Button", "x+m+45 w100 h30", "✖ Cancel")

    result := Map("ok", false, "description", "")

    HandleCreateClick(*) {
        result["ok"] := true
        result["description"] := editDesc.Value
        dlg.Destroy()
    }

    dlgBtnCreate.OnEvent("Click", HandleCreateClick)
    dlgBtnCancel.OnEvent("Click", (*) => dlg.Destroy())
    dlg.OnEvent("Close", (*) => dlg.Destroy())
    
    ; Make the dialog modal
    guiMain.Enabled := false
    dlg.Show("AutoSize")
    WinWaitClose("ahk_id " dlg.Hwnd)
    guiMain.Enabled := true

    return result
}

CreateRestorePoint(*) {
    LogDebug("Attempting to create restore point")

    ; Get description from user via custom GUI
    dialogResult := OpenCreateDialog()
    if (!dialogResult["ok"]) {
        LogDebug("Restore point creation cancelled by user.")
        return
    }
    
    ShowProgress("Creating restore point...")
    try {
        description := dialogResult["description"]
        if (Trim(description) = "") {
            description := "Restore Point created by Restore Points Manager"
        }
        
        ; Create restore point using PowerShell
        cmd := "powershell.exe -Command Checkpoint-Computer -Description '" description "' -RestorePointType 'MODIFY_SETTINGS'"
        RunWait(cmd, , "Hide")
        
        LogDebug("Restore point created successfully")
        RefreshRestorePoints()
    } catch as e {
        LogError("Failed to create restore point: " e.Message)
        MsgBox("Failed to create restore point: " e.Message, "Error", 16)
    } finally {
        HideProgress()
    }
}

DeleteRestorePoint(*) {
    selected := lvRestorePoints.GetNext(0, "F")  ; Get focused/selected items
    if (selected = 0) {
        MsgBox("Please select a restore point to delete.", "No Selection", 64)
        return
    }
    
    ; Get the restore point ID
    id := lvRestorePoints.GetText(selected, 1)
    
    result := MsgBox("Are you sure you want to delete restore point #" id "?`n`nThis action cannot be undone.", "Confirm Delete", 4)
    if (result = "No") {
        return
    }
    
    LogDebug("Deleting restore point #" id)
    ShowProgress("Deleting restore point...")
    
    try {
        ; Delete restore point using Srclient.dll
        DllCall("Srclient.dll\SRRemoveRestorePoint", "Int", id, "Int")
        
        LogDebug("Restore point #" id " deleted successfully")
        RefreshRestorePoints()
    } catch as e {
        LogError("Failed to delete restore point: " e.Message)
        MsgBox("Failed to delete restore point: " e.Message, "Error", 16)
    } finally {
        HideProgress()
    }
}