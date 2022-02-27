local function download(url, file, noerr)
    local content = http.get(url)
    if not content then
        if not noerr then
            error("Failed to access resource " .. url)
        else
            return false
        end
    end
    content = content.readAll()
    local fi = fs.open(file, "w")
    fi.write(content)
    fi.close()
end

print("You seem to have been running a legacy version of this installer.")
print("You'll have to download the new version before continuing.")
print("Download now? (y/n)")
local input = read()
if input == "y" then
    print("Downloading...")
    download("https://raw.githubusercontent.com/Minater247/CCVim/main/vim_installer.lua", "/vim/installer")
    fs.delete("/vim/installer.lua") --legacy installer no longer needed
    fs.move("/vim/installer", "/vim/vim_installer.lua")
    print("Done! Please re-run the installer using `vim_installer`.")
end