const initSqlJs = require('sql.js');
const fs = require('fs');

async function main() {
  if (!fs.existsSync('golden_db.sqlite')) {
    console.log('Database file does not exist yet.');
    return;
  }
  const SQL = await initSqlJs();
  const filebuffer = fs.readFileSync('golden_db.sqlite');
  const db = new SQL.Database(filebuffer);
  
  const res = db.exec("SELECT id, email FROM users");
  if (res.length > 0) {
     console.log('Users in DB:', res[0].values);
  } else {
     console.log('No users found.');
  }
  
  // Let's force delete admin@admin.com so the user can register again cleanly
  db.run("DELETE FROM users WHERE email = 'admin@admin.com'");
  const data = db.export();
  fs.writeFileSync('golden_db.sqlite', Buffer.from(data));
  console.log('Cleared admin@admin.com if it existed. Ready for fresh registration.');
}
main();
