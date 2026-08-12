local setup_highlight_groups = function()
  local highlightlib = require("ntf.vendor.misclib.highlight")
  return {
    --- lines with a mutant no test detected
    NtfMutationSurvived = highlightlib.link("NtfMutationSurvived", "WarningMsg"),
  }
end

return setup_highlight_groups()
