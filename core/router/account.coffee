{Router} = require 'express'
_ = require 'lodash'

utils = require '../utils'

{i18n, Account, CouponCode} = root
{requireAuthenticate} = require '../middleware'

module.exports = router = new Router()

###
  Router: GET /account

  Response {Account} from {Account::pick}
###
router.get '/', requireAuthenticate, (req, res) ->
  res.json req.account.pick 'self'

###
  Router: GET /account/register

  Response HTML.
###
router.get '/register', (req, res) ->
  res.render 'account/register'

###
  Router: GET /account/login

  Response HTML.
###
router.get '/login', (req, res) ->
  res.render 'account/login'

###
  Router: GET /account/forget

  Response HTML
###
router.get '/forget',  (req, res) ->
  res.render 'account/forget'

###
  Router: GET /account/reset/:email/:token

  Response HTML
###
router.get '/reset/:email/:token', (req, res) ->
  Account.search(req.params.email).done (account) ->
    unless account
      throw new Error 'no account'

    if account.token.length != 1 or account.token[0] != token
      throw new Error 'illegal action'

    res.render 'account/reset', req.params
  , next

###
  Router: GET /account/translations/:language?

  Response {Object}.
###
router.get '/translations/:language?', (req, res) ->
  if req.params.language
    res.json i18n.packTranslations req.params.language
  else
    res.json i18n.packTranslations req

###
  Router: GET /account/preferences/edit

  Response HTML.
###
router.get '/preferences/edit', requireAuthenticate, (req, res) ->
  res.render 'account/preferences'

###
  Router: POST /account/register

  Request {Object}

    * `username` {String}
    * `email` {String}
    * `password` {String}

  Response {Token}.
  Set-Cookie: token.
###
router.post '/register', (req, res, next) ->
  Account.register(req.body).then (account) ->
    res.createToken account
  .catch (err) ->
    if err.message.match /duplicate.*username/
      next new Error 'username exist'
    else
      next err

###
  Router: POST /account/forget

  Request {Object}

    * `email` {String}

  Response HTML send mail result page (success or failed)
###
router.post '/forget', (req, res) ->
  Account.search(req.body.email).then (account) ->
    account.forgetPassword(req.getClientInfo()).then (token) ->
      # the send mail module can't work
      # todo: send email with a url like: /account/reset/:email/:token
      # return the success or ...
      res.sendStatus 200

###
  Router: POST /account/forget

  Request {Object}

    * `email` {String}

  Response HTML send mail result page (success or failed)
###
router.post '/reset', (req, res) ->
  Account.search(req.body.email).done (account) ->
    # TODO: check token type
    if account and account.token.length is 1 and account.token[0] is req.body.token
      account.setPassword(req.body.password).then ->
        account.update
          $set:
            token: []
        .then ->
          res.json account
    else
      throw new Error 'illegal action'

  , next

###
  Router: POST /account/login

  Request {Object}

    * `username` {String} Username, email or account_id.
    * `password` {String}

  Response {Token}.
  Set-Cookie: token, language.
###
router.post '/login', (req, res, next) ->
  Account.search(req.body.username).then (account) ->
    unless account?.matchPassword req.body.password
      throw new Error 'wrong password'

    res.createCookie 'language', account.preferences.language

    res.createToken(account).then (token) ->
      req.createSecurityLog 'login', {},
        account: account
        token: token

  .catch (err) ->
    if err.message.match /must be a/
      next new Error 'wrong password'
    else
      next err

###
  Router: POST /account/logout

  Set-Cookie: token.
###
router.post '/logout', requireAuthenticate, (req, res, next) ->
  req.token.revoke().done ->
    req.createSecurityLog('revoke_token').then ->
      res.clearCookie('token').sendStatus 204
  , next

###
  Router: PUT /account/password

  Request {Object}

    * `original_password` {String}
    * `password` {String}

###
router.put '/password', requireAuthenticate, (req, res, next) ->
  Q().done ->
    unless req.account.matchPassword req.body.original_password
      throw new Error 'wrong_password'

    unless utils.rx.password.test req.body.password
      throw new Error 'invalid_password'

    req.account.setPassword(req.body.password).then ->
      req.createSecurityLog 'update_password'
      res.sendStatus 204

  , next

###
  Router: PUT /email

  Request {Object}

    * `email` {String}
    * `password` {String}

###
router.post '/update_email', requireAuthenticate, (req, res, next) ->
  Q().done ->
    unless req.account.matchPassword req.body.password
      throw new Error 'wrong_password'

    unless utils.rx.email.test req.body.email
      throw new Error 'invalid_email'

    original_email = req.account.email

    req.account.setEmail(req.body.email).then ->
      req.createSecurityLog 'update_email',
        original_email: original_email
        current_email: req.account.email

      res.sendStatus 204

  , next

###
  Router: PATCH /account/preferences

  Request {Preferences}.

  Response {Preferences}.
###
router.patch '/preferences', requireAuthenticate, (req, res, next) ->
  req.account.updatePreferences(req.body).done (preferences) ->
    res.json preferences
  , next

router.use '/plans', do (router = new Router) ->
  router.param 'plan', (req, res, next, plan_name) ->
    if req.plan = root.billing.byName plan_name
      next()
    else
      next new Error 'plan not found'

  ###
    Router: POST /account/plans/:plan/join
  ###
  router.post '/:plan/join', (req, res, next) ->
    if root.billing.isFrozen req.account
      return next new Error 'insufficient_balance'

    unless req.plan.join_freely
      return next new Error 'cant_join_plan'

    req.plan.addMember(req.account).done ->
      res.sendStatus 204
    , next

  ###
    Router: POST /account/plans/:plan/leave
  ###
  router.post '/:plan/leave', (req, res, next) ->
    req.plan.removeMember(req.account).done ->
      res.sendStatus 204
    , next

router.use '/coupons', do (router = new Router) ->
  ###
    Router: GET /account/coupons/:code

    Response {CouponCode}.
  ###
  router.get '/:code', (req, res, next) ->
    CouponCode.findByCode(req.params.code).done (coupon) ->
      if coupon
        coupon.populate(req: req).then ->
          coupon.validate(req.account).then (available) ->
            res.json _.extend coupon.pick(),
              available: available
      else
        throw new Error 'coupon_not_found'
    , next

  ###
    Router: POST /account/coupons/:code/apply
  ###
  router.post '/:code/apply', requireAuthenticate, (req, res, next) ->
    CouponCode.findByCode(req.params.code).done (coupon) ->
      if coupon
        coupon.apply(account).then ->
          res.sendStatus 204
      else
        throw new Error 'coupon_not_found'
    , next
