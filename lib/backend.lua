local Backend = {}

function Backend.current()
    return rawget(_ENV, "backend")
        or rawget(_G, "backend")
        or rawget(_ENV, "backend_proxy")
        or rawget(_ENV, "backend_ref")
end

function Backend.cwd()
    return Backend.current().cwd()
end

function Backend.chdir(path)
    return Backend.current().chdir(path)
end

function Backend.resolve_path(path)
    return Backend.current().resolve_path(path)
end

function Backend.running_program()
    return Backend.current().running_program()
end

function Backend.list_commands()
    return Backend.current().list_commands()
end

function Backend.list_locales()
    return Backend.current().list_locales()
end

function Backend.list_users()
    return Backend.current().list_users()
end

function Backend.system(command, opts)
    return Backend.current().system(command, opts)
end

function Backend.new_pipe(ipc)
    return Backend.current().new_pipe(ipc)
end

function Backend.spawn(path, opts, on_exit)
    return Backend.current().spawn(path, opts, on_exit)
end

return Backend
