-- pagebreak.lua — pandoc Lua filter
-- Converts markdown horizontal rules (---) to a generous vertical gap
-- instead of a page break or a thin horizontal line.

function HorizontalRule()
  return pandoc.RawBlock('openxml',
    '<w:p><w:pPr><w:spacing w:before="560" w:after="560"/></w:pPr></w:p>')
end
