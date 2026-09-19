// Keep prose outside HTML comments and top-level CommonMark fenced blocks.
// A fence closes with the same character and at least the opening length.
export function prose(text) {
  let fence = null, comment = false;
  const lines = [];
  for (let line of text.split(/\r?\n/)) {
    if (fence) {
      const close = line.match(/^ {0,3}(`+|~+)[ \t]*$/);
      if (close && close[1][0] === fence[0] && close[1].length >= fence.length) fence = null;
      lines.push('');
      continue;
    }
    let visible = '';
    while (line) {
      if (comment) {
        const end = line.indexOf('-->');
        if (end < 0) break;
        comment = false;
        line = line.slice(end + 3);
      }
      const start = line.indexOf('<!--');
      if (start < 0) { visible += line; break; }
      visible += line.slice(0, start);
      line = line.slice(start + 4);
      comment = true;
    }
    const open = visible.match(/^ {0,3}(`{3,}|~{3,})(.*)$/);
    if (open && !(open[1][0] === '`' && open[2].includes('`'))) fence = open[1];
    lines.push(fence ? '' : visible);
  }
  return lines.join('\n');
}
