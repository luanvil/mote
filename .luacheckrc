std = "lua51+lua52+lua53+lua54"
max_line_length = false

include_files = {
    "mote/**/*.lua",
    "spec/**/*.lua",
}

files["spec/**/*.lua"] = {
    std = "+busted",
}
