local api = vim.api

local state = { prev_input = nil }

local function label_f(kwargs)
    -- Reinvent The Wheel #1
    -- Custom targets callback, ~90% of it replicating what Leap does by default.

    local function get_input()
        vim.cmd('echo ""')
        local hl = require("leap.highlight")
        if vim.v.count == 0 and not (kwargs.unlabeled and vim.fn.mode(1):match("o")) then
            hl["apply-backdrop"](hl, kwargs.cc.backward)
        end
        hl["highlight-cursor"](hl)
        vim.cmd("redraw")
        local ch = require("leap.util")["get-input-by-keymap"]({ str = ">" })
        hl["cleanup"](hl, { vim.fn.win_getid() })
        if not ch then
            return
        end
        -- Repeat with the previous input?
        local repeat_key = require("leap.opts").special_keys.next_target
        if ch == api.nvim_replace_termcodes(repeat_key, true, true, true) then
            if state.prev_input then
                ch = state.prev_input
            else
                vim.cmd('echo "no previous search"')
                return
            end
        else
            state.prev_input = ch
        end
        return ch
    end

    local function get_pattern(input)
        -- See `expand-to-equivalence-class` in `leap`.
        -- Gotcha! 'leap'.opts redirects to 'leap.opts'.default - we want .current_call!
        local chars = require("leap.opts").eq_class_of[input]
        if chars then
            chars = vim.tbl_map(function(ch)
                if ch == "\n" then
                    return "\\n"
                elseif ch == "\\" then
                    return "\\\\"
                else
                    return ch
                end
            end, chars or {})
            input = "\\(" .. table.concat(chars, "\\|") .. "\\)" -- "\(a\|b\|c\)"
        end
        return "\\V" .. (kwargs.multiline == false and "\\%.l" or "") .. input
    end

    local function get_targets(pattern)
        local search = require("leap.search")
        local bounds = search["get-horizontal-bounds"]()
        local match_positions =
            search["get-match-positions"](pattern, bounds, { ["backward?"] = kwargs.cc.backward })
        local targets = {}
        local skipcc = vim.fn.has("nvim-0.10") == 1
        local line_str
        local prev_line
        for _, pos in ipairs(match_positions) do
            local line, col = unpack(pos)
            if line ~= prev_line then
                line_str = vim.fn.getline(line)
                prev_line = line
            end
            local start = vim.fn.charidx(line_str, col - 1)
            local ch
            if skipcc then
                ch = vim.fn.strcharpart(line_str, start, 1, 1)
            else
                ch = vim.fn.strcharpart(line_str, start, 1)
            end
            table.insert(targets, { pos = pos, chars = { ch } })
        end
        return targets
    end

    -- The actual arguments for `leap` (would-be `opts.current_call`).
    local cc = kwargs.cc or {}

    cc.targets = function()
        local state = require("leap").state
        local pattern
        if state.args.dot_repeat then
            pattern = state.dot_repeat_pattern
        else
            local input = get_input()
            if not input then
                return
            end
            pattern = get_pattern(input)
            -- Do not save into `state.dot_repeat`, because that will be
            -- replaced by `leap` completely when setting dot-repeat.
            state.dot_repeat_pattern = pattern
        end
        return get_targets(pattern)
    end

    cc.opts = kwargs.opts or {}

    require("leap").leap(cc)
end

local config = {}

local function setup(kwargs)
    config = kwargs or {}

    -- Reinvent The Wheel #2
    -- Ridiculous hack to prevent having to expose a `multiline` flag in
    -- the core: switch Leap's backdrop function to our special one here :)
    if kwargs.multiline == false then
        local state = require("leap").state
        local function backdrop_current_line()
            local hl = require("leap.highlight")
            if pcall(api.nvim_get_hl_by_name, hl.group.backdrop, false) then
                local curline = vim.fn.line(".") - 1 -- API indexing
                local curcol = vim.fn.col(".")
                local startcol = state.args.backward and 0 or (curcol + 1)
                local endcol = state.args.backward and (curcol - 1) or -1
                vim.highlight.range(
                    0,
                    hl.ns,
                    hl.group.backdrop,
                    { curline, startcol },
                    { curline, endcol },
                    { priority = hl.priority.backdrop }
                )
            end
        end
        api.nvim_create_augroup("Label_f", {})
        api.nvim_create_autocmd("User", {
            pattern = "LeapEnter",
            group = "Label_f",
            callback = function()
                if state.args.ft then
                    state.saved_backdrop_fn = require("leap.highlight")["apply-backdrop"]
                    require("leap.highlight")["apply-backdrop"] = backdrop_current_line
                end
            end,
        })
        api.nvim_create_autocmd("User", {
            pattern = "LeapLeave",
            group = "Label_f",
            callback = function()
                if state.args.ft then
                    require("leap.highlight")["apply-backdrop"] = state.saved_backdrop_fn
                    state.saved_backdrop_fn = nil
                end
            end,
        })
    end
end

return {
    setup = setup,
    label_f = function(kwargs)
        config.cc = {} --> would-be `opts.current_call`
        config.cc.ft = true
        config.cc.inclusive_op = true
        config.unlabeled = true
        config.cc = vim.tbl_extend("force", config.cc, kwargs)
        label_f(config)
    end,
}
