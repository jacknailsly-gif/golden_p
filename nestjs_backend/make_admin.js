const initSqlJs = require('sql.js');
const fs = require('fs');

async function main() {
  const SQL = await initSqlJs();
  const filebuffer = fs.readFileSync('golden_db.sqlite');
  const db = new SQL.Database(filebuffer);
  
  db.run("UPDATE users SET role = 'admin' WHERE email = 'admin04@admin.com'");
  const data = db.export();
  fs.writeFileSync('golden_db.sqlite', Buffer.from(data));
  console.log('User admin04@admin.com elevated to admin role!');
}
main();
