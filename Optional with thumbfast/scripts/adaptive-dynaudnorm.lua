local mp = require "mp"

local timer = nil
local updating = false

local current_signature = nil

local layouts = {
    ["5.0"] = {
        "FL", "FR", "FC", "BL", "BR"
    },

    ["5.0(side)"] = {
        "FL", "FR", "FC", "SL", "SR"
    },

    ["5.1"] = {
        "FL", "FR", "FC", "LFE", "BL", "BR"
    },

    ["5.1(side)"] = {
        "FL", "FR", "FC", "LFE", "SL", "SR"
    },

    ["7.0"] = {
        "FL", "FR", "FC", "BL", "BR", "SL", "SR"
    },

    ["7.0(front)"] = {
        "FL", "FR", "FC", "FLC", "FRC", "SL", "SR"
    },

    ["7.1"] = {
        "FL", "FR", "FC", "LFE",
        "BL", "BR", "SL", "SR"
    },

    ["7.1(wide)"] = {
        "FL", "FR", "FC", "LFE",
        "BL", "BR", "FLC", "FRC"
    },

    ["7.1(wide-side)"] = {
        "FL", "FR", "FC", "LFE",
        "FLC", "FRC", "SL", "SR"
    },

    ["5.1.2"] = {
        "FL", "FR", "FC", "LFE",
        "BL", "BR", "TFL", "TFR"
    },

    ["5.1.4"] = {
        "FL", "FR", "FC", "LFE",
        "BL", "BR",
        "TFL", "TFR", "TBL", "TBR"
    },

    ["7.1.2"] = {
        "FL", "FR", "FC", "LFE",
        "BL", "BR", "SL", "SR",
        "TFL", "TFR"
    },

    ["7.1.4"] = {
        "FL", "FR", "FC", "LFE",
        "BL", "BR", "SL", "SR",
        "TFL", "TFR", "TBL", "TBR"
    },

    ["9.1.4"] = {
        "FL", "FR", "FC", "LFE",
        "BL", "BR",
        "FLC", "FRC",
        "SL", "SR",
        "TFL", "TFR", "TBL", "TBR"
    },
}


local function set_filter(filter)
    -- Remove only our own filter.
    mp.commandv("af", "remove", "@adaptive-dynaudnorm")

    if filter then
        mp.commandv(
            "af",
            "add",
            "@adaptive-dynaudnorm:" .. filter
        )
    end
end


local function build_multichannel_filter(layout, channels)
    local outputs = {}
    local inputs = {}

    for _, ch in ipairs(channels) do
        outputs[#outputs + 1] = "[" .. ch .. "]"

        if ch == "FC" then
            inputs[#inputs + 1] = "[FCN]"
        else
            inputs[#inputs + 1] = "[" .. ch .. "]"
        end
    end

    -- Unlike lavfi-complex, this graph has no [aidN].
    -- The selected mpv audio track is automatically the graph input.
    return string.format(
        "channelsplit=channel_layout=%s:channels=all%s;"
        .. "[FC]dynaudnorm[FCN];"
        .. "%samerge=inputs=%d,"
        .. "channelmap=channel_layout=%s",

        layout,
        table.concat(outputs),
        table.concat(inputs),
        #channels,
        layout
    )
end


local function update()
    timer = nil
    updating = false

    local aid = mp.get_property("aid")

    -- With ordinary af=lavfi, aid remains the normal selected track.
    if not aid or aid == "no" then
        return
    end

    local count =
        mp.get_property_number(
            "audio-params/channel-count",
            0
        )

    local layout =
        mp.get_property("audio-params/channels")

    if not count
        or count <= 0
        or not layout
        or layout == ""
    then
        return
    end

    local signature =
        aid .. "|" .. layout .. "|" .. count

    if signature == current_signature then
        return
    end

    current_signature = signature

    ------------------------------------------------------------
    -- Stereo
    ------------------------------------------------------------

    if count == 2 then
        set_filter("lavfi=[dynaudnorm]")

        mp.osd_message(
            "adaptive dynaudnorm\n"
            .. "2.0 / full signal",
            2.0
        )

        mp.msg.info(
            "[adaptive-dynaudnorm] "
            .. "aid=" .. aid
            .. " layout=" .. layout
            .. " -> stereo / full signal"
        )

        return
    end


    ------------------------------------------------------------
    -- Multichannel
    ------------------------------------------------------------

    local channels = layouts[layout]

    if channels and #channels == count then

        local graph =
            build_multichannel_filter(
                layout,
                channels
            )

        set_filter(
            "lavfi=[" .. graph .. "]"
        )

        mp.osd_message(
            "adaptive dynaudnorm\n"
            .. layout
            .. " / FC only\n"
            .. "aid " .. aid,
            2.0
        )

        mp.msg.info(
            "[adaptive-dynaudnorm] "
            .. "aid=" .. aid
            .. " layout=" .. layout
            .. " -> FC only"
        )

        return
    end


    ------------------------------------------------------------
    -- Unknown layout
    ------------------------------------------------------------

    set_filter(nil)

    mp.osd_message(
        "adaptive dynaudnorm\n"
        .. layout
        .. " / unsupported — untouched",
        2.0
    )

    mp.msg.info(
        "[adaptive-dynaudnorm] "
        .. "aid=" .. aid
        .. " layout=" .. layout
        .. " -> unsupported / untouched"
    )
end


local function schedule()
    if updating then
        return
    end

    updating = true

    timer = mp.add_timeout(
        0.10,
        update
    )
end


mp.observe_property(
    "aid",
    "string",
    schedule
)

mp.observe_property(
    "audio-params/channels",
    "string",
    schedule
)

mp.observe_property(
    "audio-params/channel-count",
    "number",
    schedule
)

mp.register_event(
    "file-loaded",
    schedule
)

mp.register_event(
    "tracks-changed",
    schedule
)

schedule()