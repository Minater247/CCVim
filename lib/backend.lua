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

return Backend
