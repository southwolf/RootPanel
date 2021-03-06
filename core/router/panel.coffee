{Router} = require 'express'
_ = require 'lodash'
Q = require 'q'

{Account, Financials} = root
{requireAuthenticate} = require '../middleware'

module.exports = router = new Router()

router.use requireAuthenticate

###
  Router: GET /panel/financials

  Response HTML.
###
router.get '/financials', (req, res, next) ->
  Q.all([
    null
    Financials.getDepositLogs req.account, req: req, limit: 10
    Financials.getBillingLogs req.account, limit: 10
  ]).done ([payment_providers, deposit_logs, billing_logs]) ->
    res.render 'panel/financials',
      deposit_logs: deposit_logs
      billing_logs: billing_logs
  , next

###
  Router: GET /panel/components

  Response HTML.
###
router.get '/components', (req, res) ->
  res.render 'panel/components',
    component_providers: root.components.all()

###
  Router: GET /panel

  Response HTML.
###
router.get '/', (req, res, next) ->
  root.widgets.dispatch('panel', req.account).done (widgets_html) ->
    res.render 'panel',
      widgets_html: widgets_html
  , next
