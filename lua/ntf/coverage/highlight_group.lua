local setup_highlight_groups = function()
  local highlightlib = require("ntf.vendor.misclib.highlight")
  return {
    --- covered lines
    NtfCoverageCovered = highlightlib.link("NtfCoverageCovered", "DiffAdd"),
    --- coverable-but-missed lines
    NtfCoverageMissed = highlightlib.link("NtfCoverageMissed", "DiffDelete"),
  }
end

return setup_highlight_groups()
