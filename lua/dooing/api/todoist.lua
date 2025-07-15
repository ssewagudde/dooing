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

--- Get or create the "in_progress" label in Todoist
--- @return string|nil Label ID for in_progress
local function get_in_progress_label()
    -- First, try to get existing labels
    local url = "https://api.todoist.com/rest/v2/labels"
    local res = curl({ url })
    if res and res ~= "" then
        local ok, labels = pcall(vim.fn.json_decode, res)
        if ok and type(labels) == "table" then
            for _, label in ipairs(labels) do
                if label.name == "in_progress" then
                    return label.id
                end
            end
        end
    end
    
    -- Create the label if it doesn't exist
    local create_url = "https://api.todoist.com/rest/v2/labels"
    local payload = vim.fn.json_encode({ name = "in_progress" })
    local create_res = curl({
        "-H", "Content-Type: application/json",
        "-X", "POST",
        create_url,
        "-d", payload,
    })
    if create_res and create_res ~= "" then
        local ok, label = pcall(vim.fn.json_decode, create_res)
        if ok and label.id then
            return label.id
        end
    end
    
    return nil
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
    
    -- Get the in_progress label ID for status detection
    local in_progress_label_id = get_in_progress_label()
    
    -- Add status field based on labels
    for _, task in ipairs(data) do
        task.dooing_status = "pending" -- default
        if task.labels and in_progress_label_id then
            for _, label_id in ipairs(task.labels) do
                if tostring(label_id) == tostring(in_progress_label_id) then
                    task.dooing_status = "in_progress"
                    break
                end
            end
        end
    end
    
    return data
end

--- Set task status by managing the in_progress label
--- @param id number|string Task ID
--- @param status string "pending", "in_progress", or "done"
function M.set_task_status(id, status)
    local in_progress_label_id = get_in_progress_label()
    if not in_progress_label_id then
        vim.notify("Failed to get in_progress label", vim.log.levels.WARN, { title = "Dooing" })
        return
    end
    
    -- Get current task to check existing labels
    local task_url = string.format("https://api.todoist.com/rest/v2/tasks/%s", id)
    local task_res = curl({ task_url })
    if not task_res or task_res == "" then
        return
    end
    
    local ok, task = pcall(vim.fn.json_decode, task_res)
    if not ok or not task.labels then
        return
    end
    
    local current_labels = {}
    local has_in_progress = false
    
    -- Copy existing labels, excluding in_progress
    for _, label_id in ipairs(task.labels) do
        if tostring(label_id) ~= tostring(in_progress_label_id) then
            table.insert(current_labels, label_id)
        else
            has_in_progress = true
        end
    end
    
    -- Add in_progress label if needed
    if status == "in_progress" and not has_in_progress then
        table.insert(current_labels, in_progress_label_id)
    end
    
    -- Update task labels
    local update_payload = vim.fn.json_encode({ labels = current_labels })
    curl({
        "-H", "Content-Type: application/json",
        "-X", "POST",
        task_url,
        "-d", update_payload,
    })
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