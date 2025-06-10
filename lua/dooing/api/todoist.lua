local M = {}
local config = require("dooing.config")

-- Utility to run curl commands via vim.fn.system
local function curl(cmd_args)
    -- Determine API token: config option takes precedence, fallback to environment var
    local token = config.options.todoist_api_token
    if not token or token == "" then
        token = os.getenv("TODOIST_API_TOKEN")
    end
    if not token or token == "" then
        vim.notify(
            "Todoist API token is not set. Please set todoist_api_token in your setup or export TODOIST_API_TOKEN.",
            vim.log.levels.ERROR,
            { title = "Dooing" }
        )
        return nil
    end
    -- Prepend Authorization header, follow redirects (-L)
    local header = "Authorization: Bearer " .. token
    -- Build full command: silent, follow redirects
    local cmd = { "curl", "-sL", "-H", header }
    for _, arg in ipairs(cmd_args) do
        table.insert(cmd, arg)
    end
    local ok, result = pcall(vim.fn.system, cmd)
    if not ok then
        vim.notify("Error running curl: " .. tostring(result), vim.log.levels.ERROR, { title = "Dooing" })
        return nil
    end
    return result
end

--- Fetch all tasks from Todoist
--- @return table|nil Array of task objects
function M.get_tasks()
    -- Use Todoist REST API v2 to fetch open tasks
    local url = "https://api.todoist.com/rest/v2/tasks"
    local res = curl({ url })
    if not res or res == "" then
        return {}
    end
    local ok, data = pcall(vim.fn.json_decode, res)
    if not ok or type(data) ~= "table" then
        local snippet = type(res) == "string" and res:sub(1, 200) or ""
        vim.notify(
            "Failed to decode Todoist tasks JSON. Response snippet: " .. snippet,
            vim.log.levels.ERROR,
            { title = "Dooing" }
        )
        return {}
    end
    return data
end

--- Add a new task to Todoist
--- @param content string
--- @return table|nil Created task object
function M.add_task(content)
    local url = "https://api.todoist.com/rest/v2/tasks"
    local payload = vim.fn.json_encode({ content = content })
    local res = curl({
        "-H", "Content-Type: application/json",
        "-X", "POST",
        url,
        "-d", payload,
    })
    if not res or res == "" then
        vim.notify("Failed to add Todoist task: empty response", vim.log.levels.ERROR, { title = "Dooing" })
        return nil
    end
    local ok, task = pcall(vim.fn.json_decode, res)
    if not ok then
        vim.notify("Failed to decode Todoist add-task response", vim.log.levels.ERROR, { title = "Dooing" })
        return nil
    end
    return task
end

--- Close (complete) a task in Todoist via REST v2
--- @param id number|string
function M.close_task(id)
    local url = string.format("https://api.todoist.com/rest/v2/tasks/%s/close", id)
    curl({ "-X", "POST", url })
end

--- Reopen (un-complete) a task in Todoist via REST v2
--- @param id number|string
function M.reopen_task(id)
    local url = string.format("https://api.todoist.com/rest/v2/tasks/%s/reopen", id)
    curl({ "-X", "POST", url })
end

--- Delete a task in Todoist via REST v2
--- @param id number|string
function M.delete_task(id)
    local url = string.format("https://api.todoist.com/rest/v2/tasks/%s", id)
    curl({ "-X", "DELETE", url })
end

--- Update a task in Todoist (PATCH with arbitrary fields)
--- @param id number|string
--- @param data table JSON-serializable fields to update
--- @return table|nil Updated task object
function M.update_task(id, data)
    local url = string.format("https://api.todoist.com/rest/v2/tasks/%s", id)
    local payload = vim.fn.json_encode(data)
    local res = curl({
        "-H", "Content-Type: application/json",
        "-X", "POST",
        url,
        "-d", payload,
    })
    if not res or res == "" then
        return nil
    end
    local ok, task = pcall(vim.fn.json_decode, res)
    if not ok or type(task) ~= "table" then
        return nil
    end
    return task
end

return M