data:extend {
    {
        type = "string-setting",
        name = "FunkedOre-transform-string",
        setting_type = "runtime-global",
        default_value = "",
        allow_blank = true,
        order = "1",
    }, -- NOTE not sure if there's a length limit, but if there is it's over 187 chars
    {
        type = "int-setting",
        name = "FunkedOre-min-distance-from-spawn",
        setting_type = "runtime-global",
        default_value = 0,
        order = "2",
    },
    {
        type = "int-setting",
        name = "FunkedOre-control-point-reach-dist",
        setting_type = "runtime-global",
        default_value = 80,
        order = "3",
    },
    {
        type = "int-setting",
        name = "FunkedOre-control-point-early-stop-dist",
        setting_type = "runtime-global",
        default_value = 20,
        order = "4",
    },
    {
        type = "int-setting",
        name = "FunkedOre-control-point-reproduce-after-dist",
        setting_type = "runtime-global",
        default_value = 20,
        order = "5",
    },
}