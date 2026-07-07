function setHiddenRowCol(table: any, worksheet: any) {
  for (let row in table.config?.rowhidden) {
    worksheet.getRow(parseInt(row) + 1).hidden = true;
  }
  for (let col in table.config?.colhidden) {
    worksheet.getColumn(parseInt(col) + 1).hidden = true;
  }
}

export { setHiddenRowCol };
