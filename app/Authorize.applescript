on runcontrol(toolPath, actionName, desktopUID)
    set commandText to (quoted form of toolPath) & space & (quoted form of actionName)
    if actionName is in {"start", "install", "remove"} then set commandText to commandText & space & (quoted form of desktopUID)
    try
        set details to do shell script commandText with administrator privileges
        return {"ok", details}
    on error details number code
        if code is -128 then return {"cancel", ""}
        return {"error", details}
    end try
end runcontrol
