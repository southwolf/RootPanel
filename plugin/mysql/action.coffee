mysql = require 'mysql'

plugin = require '../../core/plugin'
{assertInService} = require '../../core/router/middleware'

module.exports = exports = express.Router()

exports.use assertInService 'mysql'

exports.post '/update_password/', (req, res) ->
  unless req.body.password or /^[A-Za-z0-9\-_]+$/.test req.body.password
    return res.error 'invalid_password'

  connection = mysql.createConnection config.plugins.mysql.connection
  connection.connect()

  connection.query "SET PASSWORD FOR '#{req.account.username}'@'localhost' = PASSWORD('#{req.body.password}');", (err, rows, fields) ->
    throw err if err
    connection.end()
    res.json {}
