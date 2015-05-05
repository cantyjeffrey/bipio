## Router

This is the ExpressJS REST API front-end routing wrapper.

	app = module.parent.exports.app
	dao = null
	bastion = null
	util = require('util')
	express = require('express')
	connect = require('connect')
	helper = require('./lib/helper')
	uuid = require('node-uuid')
	pkg = require('../package.json')
	restResources = [
		'bip'
		'channel'
		'domain'
		'account_option'
	]
	modelPublicFilter = null

#### filterModel

	filterModel = (filterLen, modelPublicFilters, modelStruct, decode) ->
		result = {}
		i = 0
		while i < filterLen
			publicAttribute = modelPublicFilters[i]
			if modelStruct[publicAttribute]
				result[publicAttribute] = modelStruct[publicAttribute]
			i++
		result

		###
			if decode
				return helper.naturalize(result);
			else
				return helper.pasteurize(result);
		###

#### publicFilter

takes a result JSON struct and filters out whatever is not in a public filter for the supplied model. Public filter means readable flag is 'true' in the rest exposed model

	publicFilter = (modelName, modelStruct) ->
		result = {}
		filterLen = null
		modelLen = null
		publicAttribute = null
		context = modelStruct
		modelPublicFilters = null
		if modelName
			modelPublicFilters = modelPublicFilter[modelName]['read']
		else
			modelPublicFilters = []

always allow representations and meta data

		modelPublicFilters.push '_repr'
		modelPublicFilters.push '_href'
		modelPublicFilters.push '_links'
		modelPublicFilters.push 'status'
		modelPublicFilters.push 'message'
		modelPublicFilters.push 'code'
		modelPublicFilters.push 'errors'
		filterLen = modelPublicFilters.length

if it looks like a collection, then filter into the collection

		if modelStruct?.data
			for key of modelStruct
				`key = key`
				if key is 'data'
					result['data'] = []
					context = modelStruct.data
					modelLen = context.length

filter every model in the collection

					i = 0
					while i < modelLen
						result['data'].push filterModel(filterLen, modelPublicFilters, context[i], true)
						i++
				else
					result[key] = modelStruct[key]
		else
			result = filterModel(filterLen, modelPublicFilters, modelStruct, true)
		result

#### restAuthWrapper

Wrapper for connect.basicAuth. Checks the session for an authed flag and if fails, defers to http basic auth.

	restAuthWrapper = (req, res, next) ->
		if !req.header('authorization') and req.session.account and req.session.account.host is getClientInfo(req).host and !req.masqUser
			app.modules.auth.getAccountStruct req.session.account, (err, accountInfo) ->
				if !err
					req.remoteUser = req.user = accountInfo
					next()
				else
					res.status(401).end()
		else
			return connect.basicAuth((user, pass, next) ->
				app.modules.auth.test user, pass, { masquerade: req.masqUser }, next
			)(req, res, next)

#### getReferer

	getReferer = (req) ->
		referer = req.query.referer
		if not referer
			referer = req.header('Referer')
			return null
		else
			return helper.getDomainTokens referer

#### getClientInfo

	getClientInfo = (req, txId) ->
		{
			'id': txId or uuid.v4()
			'host': req.header('X-Forwarded-For') or req.connection.remoteAddress
			'date': Math.floor((new Date).getTime() / 1000)
			'proto': 'http'
			'reply_to': ''
			'method': req.method
			'content_type': helper.getMime(req)
			'encoding': req.encoding
			'headers': req.headers
		}

#### channelRender

	channelRender = (ownerId, channelId, renderer, req, res) ->
		filter = 
			owner_id: ownerId
			id: channelId
		dao.find 'channel', filter, (err, result) ->
			if err or !result
				res.status(404).end()
			else
				dao.modelFactory('channel', result).rpc renderer, req.query, getClientInfo(req), req, res

#### bipBasicFail

BIP RPC

	bipBasicFail = (req, res) ->
		connect.basicAuth((username, password, cb) ->
			cb false, false
		) req, res

#### bipAuthWrapper

Authenticate the bip before we pass it through.	If there's no bip found, the bip has auth = token or the domain doesn't exist, then fall through to an account level auth (although the account auth for nx domain shouldn't ever succeed).

We don't want to let people interrogate whether or not a HTTP exists based on the auth response (or non-response).	Therefore, always prompt for HTTP auth on this endpoint unless the bip is explicitly 'none'.

	bipAuthWrapper = (req, res, cb) ->
		app.modules.auth.domainAuth helper.getDomain(req.headers.host, true), (err, acctResult) ->
			if err
				# reject always
				bipBasicFail req, res
			else
				filter =
					'name': req.params.bip_name
					'type': 'http'
					'paused': false
					'domain_id': acctResult.domain_id
				dao.find 'bip', filter, (err, result) ->
					if !err and result
						if result.config.auth is 'none'
							req.remoteUser = acctResult
							cb false, true
						else
							connect.basicAuth((username, password, next) ->
								if 'basic' is result.config.auth
									authed = result.config.username and result.config.username is username and result.config.password and result.config.password is password
									if authed
										app.modules.auth.test result.owner_id, password, {
											acctBind: true
											asOwner: true
											masquerade: req.masqUser
										}, next
									else
										bipBasicFail req, res
								else if 'token' is result.config.auth
									app.modules.auth.test username, password, { masquerade: req.masqUser }, next
								else
									bipBasicFail req, res
							) req, res, cb
					else
						bipBasicFail req, res

#### restResponse

Normalizes response data, catches errors etc.

	restResponse = (res) ->
		(error, modelName, results, code, options) ->
			contentType = DEFS.CONTENTTYPE_JSON
			if options
				if options.content_type
					contentType = options.content_type
			res.contentType contentType

Post filter. Don't expose attributes that aren't in the public filter list.

			if null is not modelName and results
				if results instanceof Array
					realResult = []
					for key of results
						`key = key`
						realResult.push publicFilter(modelName, results[key])
				else
					realResult = publicFilter(modelName, results)
			else
				realResult = results
			payload = realResult
			if error
				if !code
					code = 500
					app.logmessage 'Error response propogated without code', 'warning'
				res.status(code).send message: error.toString()
				return
			else
				if !results
					res.status(404).end()
					return

results should contain a '_redirect' url

			if code is 301
				res.redirect results._redirect
				return
			if contentType is DEFS.CONTENTTYPE_JSON
				res.status(if !code then '200' else code).jsonp payload
			else
				res.status(if !code then '200' else code).send payload
			return

#### restAction

Generic RESTful handler for restResources

	restAction = (req, res) ->
		rMethod = req.method
		accountInfo = req.remoteUser
		owner_id = accountInfo.getId()
		resourceName = req.params.resource_name
		resourceId = req.params.id
		subResourceId = req.params.subresource_id
		postSave = null

User is authenticated and the requested model is marked as restful?
		
		if owner_id and helper.indexOf(restResources, resourceName) is not -1
			if rMethod is 'POST' or rMethod is 'PUT'
				
hack for bips, inject a referer note if no note has been sent
				
				if resourceName is 'bip'
					referer = getReferer(req)
					if null is not referer
						if null is req.body.note
							req.body.note = 'via ' + referer.url_tokens.hostname
						
inject the referer favicon
						
						if null is req.body.icon and -1 is referer.url_tokens.hostname.indexOf(CFG.domain.replace(/:\d*$/, '')) and -1 is referer.url_tokens.hostname.indexOf(CFG.domain_public.replace(/:\d*$/, ''))

							postSave = (err, modelName, retModel, code) ->
								`var model`
								`var writeFilters`
								if !err and retModel.icon is ''
									app.helper.syncFavicon referer.url_tokens.href, (err, icoURL) ->
										if !err
											dao.updateColumn 'bip', retModel.id, icon: icoURL
										return
								return

				model = null
				if rMethod is 'POST'

populate our model with the request. Set an owner_id to be the authenticated user before doing anything else
				
					model = dao.modelFactory(resourceName, helper.pasteurize(req.body), accountInfo, true)
					dao.create model, restResponse(res), accountInfo, postSave
				else if rMethod is 'PUT'

filter request body to public writable
				
					writeFilters = modelPublicFilter[resourceName]['write']
					if null is not req.body.id
						dao.update resourceName, req.body.id, filterModel(writeFilters.length, writeFilters, req.body), restResponse(res), accountInfo
					else
						res.status(404).end()
			else if rMethod is 'DELETE'
				if 'bip' is resourceName and 'logs' is subResourceId
					dao.removeFilter 'bip_log', { bip_id: req.params.id }, restResponse(res)
				else if null is not req.params.id
					dao.remove resourceName, req.params.id, accountInfo, restResponse(res)
				else
					res.status(404).end()
			else if rMethod is 'PATCH'
				if null is not req.params.id
					writeFilters = modelPublicFilter[resourceName]['write']
					dao.patch resourceName, req.params.id, filterModel(writeFilters.length, writeFilters, req.body), accountInfo, restResponse(res)
				else
					res.status(404).end()
			else if rMethod is 'GET'
				filter = {}
				
handle sub-collections
				
				if 'bip' is resourceName and 'logs' is subResourceId
					filter.bip_id = req.params.id
					resourceName = 'bip_log'
					req.params.id = null
				else if 'channel' is resourceName and 'bips' is subResourceId
					filter._channel_idx = resourceId
					resourceName = 'bip'
					req.params.id = null
				else if 'channel' is resourceName and 'logs' is subResourceId
					filter.channel_id = req.params.id
					resourceName = 'channel_log'
					req.params.id = null
				if null is not req.params.id
					if resourceName is 'channel' and (req.params.id is 'actions' or req.params.id is 'emitters')
						dao.listChannelActions req.params.id, accountInfo, restResponse(res)
					else
						model = dao.modelFactory(resourceName, {}, accountInfo)
						dao.get model, req.params.id, accountInfo, restResponse(res)
				else
					page_size = 10
					page = 1
					order_by = 'recent'
					if null is not req.query.page_size and req.query.page_size
						page_size = parseInt(req.query.page_size)
					if null is not req.query.page
						page = parseInt(req.query.page)
					if null is not req.query.order_by and (req.query.order_by is 'recent' or req.query.order_by is 'active' or req.query.order_by is 'alphabetical')
						order_by = req.query.order_by
					
extract filters
					
					if null is not req.query.filter
						tokens = req.query.filter.split(',')
						for i of tokens
							`i = i`
							filterVars = tokens[i].split(':')
							if null is not filterVars[0] and null is not filterVars[1]
								filter[filterVars[0]] = filterVars[1]
					dao.list resourceName, accountInfo, page_size, page, order_by, filter, restResponse(res)
		else
			res.status(404).end()
		return

	module.exports = {
		init: (express, _dao) ->
			dao = _dao
			modelPublicFilter = _dao.getModelPublicFilters()
				
attach any modules which are route aware
			
			for k of app.modules
				if app.modules.hasOwnProperty(k) and app.modules[k].routes
					app.modules[k].routes express, restAuthWrapper

			express.post '/rest/:resource_name', restAuthWrapper, restAction
			express.get '/rest/:resource_name/:id?', restAuthWrapper, restAction
			express.get '/rest/:resource_name/:id?/:subresource_id?', restAuthWrapper, restAction
			express.put '/rest/:resource_name/:id?', restAuthWrapper, restAction
			express.delete '/rest/:resource_name/:id/:subresource_id?', restAuthWrapper, restAction
			express.patch '/rest/:resource_name/:id', restAuthWrapper, restAction
			express.options '*', (req, res) ->
				res.status(200).end()

Pass through HTTP Bips

			express.all '/bip/http/:bip_name', bipAuthWrapper, (req, res) ->
				txId = uuid.v4()
				client = getClientInfo(req, txId)
				files = []
				contentParts = {}
				contentType = helper.getMime(req)
				encoding = req.encoding
				statusMap = 
					'success': 200
					'fail': 404
				bipName = req.params.bip_name
				domain = helper.getDomain(req.headers.host, true)
				_.each req.files, (file) ->
					files.push file
					return
				GLOBAL.app.bastion.bipUnpack 'http', bipName, req.remoteUser, client, (err, bip) ->
					exports = 'source': {}

setup source exports for this bip

					if bip and bip.config.exports and bip.config.exports.length > 0
						exportLen = bip.config.exports.length
						key = null
						i = 0
						while i < exportLen
							key = bip.config.exports[i]
							if req.query[key]
								exports.source[key] = req.query[key]
							i++
					else
						exports.source = if 'GET' is req.method then req.query else req.body
						#exports.source._body = /xml/.test(utils.mime(req)) ? req.rawBody : req.body;
						exports.source._body = req.rawBody
					restReponse = true

forward to bastion

					if !err
						exports._client = client
						exports._bip = bip

Renderer Invoke, send a repsonse

						if bip.config.renderer

get channel

							channelRender bip.owner_id, bip.config.renderer.channel_id, bip.config.renderer.renderer, req, res
							restReponse = false
						GLOBAL.app.bastion.bipFire bip, exports, client, contentParts, files
					if restReponse
						bipResp = status: 'OK'
						if err
							bipResp.status = 'ERROR'
							bipResp.message = err
						restResponse(res) err, null, bipResp, if err then 404 else 200

#### OEmbed widget endpoints

			express.get '/rpc/oembed/*', (req, res) ->
				if req.query.url and GLOBAL.CFG.oembed_host
					shareId = req.query.url.split('/')[req.query.url.split('/').length - 1]
					dao.find 'bip_share', { id: shareId }, (err, result) ->
						if err
							res.status(500).json err
						res.json
							version: '1.0'
							type: 'rich'
							provider_name: 'Bipio'
							provider_url: GLOBAL.CFG.website_public
							width: '470'
							height: '94'
							html: '<iframe src="' + GLOBAL.CFG.oembed_host + '/widget/?payload=' + new Buffer(JSON.stringify(result)).toString('base64') + '" allowtransparency="true" style="border: none; overflow: hidden;" width="470" height="94"></iframe>'
				else
					res.status(404).end()

#### Transforms RPC

			express.get '/rpc/transforms', (req, res) ->
				dao.list 'transform_default', null, 100, 1, 'recent', { owner_id: 'system' }, (err, modelName, results) ->
					res.json results

#### Describe RPC

			express.get '/rpc/describe/:model/:model_subdomain?', restAuthWrapper, (req, res) ->
				model = req.params.model
				model_subdomain = req.params.model_subdomain
				res.contentType DEFS.CONTENTTYPE_JSON
				dao.describe model, model_subdomain, restResponse(res), req.remoteUser

#### DomainAuth channel renderer

*deprecated:* /rpc/render/channel/:channel_id/:renderer

			express.get '/rpc/render/channel/:channel_id/:renderer', restAuthWrapper, (req, res) ->
				filter = 
					owner_id: req.remoteUser.getId()
					id: req.params.channel_id
				dao.find 'channel', filter, (err, result) ->
					if err or !result
						app.logmessage err, 'error'
						res.status(404).end()
					else
						channel = dao.modelFactory('channel', result, req.remoteUser)
						channel.rpc req.params.renderer, req.query, getClientInfo(req), req, res

			express.get '/rpc/channel/:channel_id/:renderer/:extra_params?/:extra_params_value?', restAuthWrapper, (req, res) ->
				filter = 
					owner_id: req.remoteUser.getId()
					id: req.params.channel_id
				dao.find 'channel', filter, (err, result) ->
					if err or !result
						app.logmessage err, 'error'
						res.status(404).end()
					else
						channel = dao.modelFactory('channel', result, req.remoteUser)
						channel.rpc req.params.renderer, req.query, getClientInfo(req), req, res

#### OAuth RPC

sets up oAuth for the selected pod, if the pod supports oAuth

			express.all '/rpc/oauth/:pod/:auth_method', restAuthWrapper, (req, res) ->
				podName = req.params.pod
				pod = dao.pod(podName)
				method = req.params.auth_method

check that authentication is supported/required by this pod

				if pod
					if !pod.oAuthRPC(method, req, res)
						res.status(415).end()
				else
					res.status(404).end()

#### Issuer Token RPC

sets up issuer_token (API keypair) for the selected pod, if the pod supports issuer_token.

			express.all '/rpc/issuer_token/:pod/:auth_method', restAuthWrapper, (req, res) ->
				podName = req.params.pod
				pod = dao.pod(podName)
				method = req.params.auth_method

check that authentication is supported/required by this pod

				if !pod.issuerTokenRPC(method, req, res)
					res.status(415).end()

#### Pod RPC

			express.get '/rpc/pod/:pod/render/:method/:arg?', restAuthWrapper, (req, res) ->
				do (req, res) ->
					method = req.params.method
					accountInfo = req.remoteUser
					channel = dao.modelFactory('channel',
						owner_id: accountInfo.user.id
						action: req.params.pod + '.')
					pod = channel.getPods(req.params.pod)
					if pod and method
						req.remoteUser = accountInfo
						if req.params.arg
							req.query._requestArg = req.params.arg
						channel.rpc method, req.query, getClientInfo(req), req, res
					else
						res.status(404).end()

			express.get '/rpc/render/pod/:pod/:method/:arg?', restAuthWrapper, (req, res) ->
				do (req, res) ->
					method = req.params.method
					accountInfo = req.remoteUser
					channel = dao.modelFactory('channel',
						owner_id: accountInfo.user.id
						action: req.params.pod + '.')
					pod = channel.getPods(req.params.pod)
					if pod and method
						req.remoteUser = accountInfo
						if req.params.arg
							req.query._requestArg = req.params.arg
						channel.rpc method, req.query, getClientInfo(req), req, res
					else
						res.status(404).end()

Pass through an RPC call to a pod

			express.get '/rpc/pod/:pod/:action/:method/:channel_id?', restAuthWrapper, (req, res) ->
				do (req, res) ->
					pod = dao.pod(req.params.pod)
					action = req.params.action
					method = req.params.method
					cid = req.params.channel_id
					accountInfo = req.remoteUser
					if pod and action and method
						req.remoteUser = accountInfo
						if cid
							filter = 
								owner_id: accountInfo.id
								id: cid
							dao.find 'channel', filter, (err, result) ->
								`var pod`
								if err or !result
									app.logmessage err, 'error'
									res.status(404).end()
								else
									channel = dao.modelFactory('channel', result)
									podTokens = channel.getPodTokens()
									pod = dao.pod(podTokens.pod)
									pod.rpc podTokens.action, method, req, restResponse(res), channel
								return
						else
							channel = dao.modelFactory('channel',
								owner_id: accountInfo.user.id
								action: pod.getName() + '.' + action)
							channel.rpc method, req.query, getClientInfo(req), req, res
					else
						res.status(404).end()

			express.post '/rpc/:method_domain?/:method_name?/:resource_id?/:subresource_id?', restAuthWrapper, (req, res) ->
				res.contentType DEFS.CONTENTTYPE_JSON
				response = {}
				methodDomain = req.params.method_domain
				method = req.params.method_name
				resourceId = req.params.resource_id
				subResourceId = req.params.subresource_id
				accountInfo = req.remoteUser
				if methodDomain is 'bip'
					if method is 'share'
						filter = 
							'owner_id': accountInfo.getId()
							'id': resourceId
						shareModel = helper.pasteurize(req.body)
						dao.shareBip dao.modelFactory('bip', shareModel, accountInfo, true), null, restResponse(res)

### Catchalls

#### RPC catchall

			express.get '/rpc/:method_domain?/:method_name?/:resource_id?/:subresource_id?', restAuthWrapper, (req, res) ->
				`var filter`
				res.contentType DEFS.CONTENTTYPE_JSON
				response = {}
				methodDomain = req.params.method_domain
				method = req.params.method_name
				resourceId = req.params.resource_id
				subResourceId = req.params.subresource_id
				accountInfo = req.remoteUser
				if methodDomain is 'get_referer_hint'
					referer = req.query.referer
					if null is referer
						referer = req.header('Referer')
					if null is referer
						response = 400
					else
						result = helper.getDomainTokens(referer)
						response.hint = (if result.url_tokens.auth then result.url_tokens.auth + '_' else '') + result.domain
						response.referer = referer
						response.scheme = result.url_tokens.protocol.replace(':', '')
					res.send response

attempts to create a bip from the referer using default settings.

				else if methodDomain is 'bip'
					if method is 'create_from_referer'
						result = getReferer(req)
						if null is result
							response = 400
							res.send response
						else

inject the bip POST handler

							req.method = 'POST'
							req.params.resource_name = 'bip'
							req.body =
								'name': (if result.url_tokens.auth then result.url_tokens.auth + '_' else '') + result.domain
								'note': 'via ' + result.url_tokens.hostname
							restAction req, res
					else if method is 'get_transform_hint'
						from = req.query.from
						to = req.query.to
						if from and to
							dao.getTransformHint accountInfo, from, to, restResponse(res)
						else
							response = 400
							res.send response
					else if method is 'share' and resourceId
						if resourceId is 'list'
							page_size = 10
							page = 1
							order_by = 'recent'
							filter = {}
							if null is not req.query.page_size
								page_size = parseInt(req.query.page_size)
							if null is not req.query.page
								page = parseInt(req.query.page)
							dao.listShares page, page_size, order_by, req.query.filter, restResponse(res)
						else
							if subResourceId and 'test' is subResourceId
								filter = 
									'owner_id': accountInfo.getId()
									'bip_id': resourceId
								dao.find 'bip_share', filter, (err, result) ->
									`var filter`
									if err or !result
										res.status(404).end()
									else
										res.status(200).end()
									return
							else
								filter = 
									'owner_id': accountInfo.getId()
									'id': resourceId
								dao.find 'bip', filter, (err, result) ->
									`var filter`
									`var accountInfo`
									`var filter`
									`var accountInfo`
									if err or !result
										app.logmessage err, 'error'
										res.status(404).end()
									else
										triggerConfig = req.query.triggerConfig
										if triggerConfig
											try
												triggerConfig = app.helper.pasteurize(JSON.parse(triggerConfig))
											catch e
												triggerConfig = {}
												app.logmessage e, 'error'
										dao.shareBip dao.modelFactory('bip', result, accountInfo, true), triggerConfig, restResponse(res)

					else if method is 'unshare' and resourceId
						accountInfo = req.remoteUser
						filter = 
							'owner_id': accountInfo.getId()
							'id': resourceId
						dao.unshareBip resourceId, accountInfo, restResponse(res)

alias into account options.	Returns RESTful account_options resource

					else if method is 'set_default' and resourceId
						accountInfo = req.remoteUser
						filter = 'owner_id': accountInfo.getId()
						dao.find 'account_option', filter, (err, result) ->
							`var filter`
							if err or !result
								res.status(404).end()
							else
								dao.setDefaultBip resourceId, dao.modelFactory('account_option', result, accountInfo), accountInfo, restResponse(res)
							return
					else if method is 'trigger' and resourceId
						filter = 
							id: resourceId
							owner_id: accountInfo.getId()
							type: 'trigger'
						respond = restResponse(res)
						dao.find 'bip', filter, (err, result) ->
							`var filter`
							`var accountInfo`
							if err
								respond.apply this, arguments
							else if !result
								respond false, 'bip'
							else
								dao.triggerAll ((err) ->
									if err
										respond 'Internal Server Error', 'bip', null, 500
									else
										respond false, 'bip', message: 'OK'
								), { id: result.id }, false, true
					else
						res.status(400).end()
				else if methodDomain is 'domain'

confirms a domain has been properly configured.	If currently set as !_available, then enables it.
					
					if method is 'confirm'
						accountInfo = req.remoteUser
						filter = 
							'owner_id': accountInfo.getId()
							'id': resourceId
						dao.find 'domain', filter, (err, result) ->
							if err or !result
								res.status(404).end()
							else
								domain = dao.modelFactory('domain', result, accountInfo, true)
								domain.verify accountInfo, restResponse(res)
					else
						res.send response
				else
					res.status(400).end()
			
			express.get '/login', (req, res) ->
				authorization = req.headers.authorization
				
				if !authorization
					res.statusCode = 401
					res.setHeader 'WWW-Authenticate', 'Basic realm="Authorization Required"'
					res.end 'Unauthorized'
					return
				
				parts = authorization.split(' ')
				
				if parts.length is not 2
					res.status(400).end()
					return
				
				scheme = parts[0]
				credentials = new Buffer(parts[1], 'base64').toString()
				index = credentials.indexOf(':')
				
				if 'Basic' is not scheme or index < 0
					res.status(400).end()
					return
				
				user = credentials.slice(0, index)
				pass = credentials.slice(index + 1)
				app.modules.auth.test user, pass, { masquerade: req.masqUser }, (err, result) ->
					if err
						res.status(401).end()
					else
						req.session.account =
							owner_id: result.user.id
							username: result.user.username
							name: result.user.name
							is_admin: result.user.is_admin
							host: getClientInfo(req).host
						if result._remoteBody
							result.user.settings['remote_settings'] = result._remoteBody or {}
						res.send publicFilter('account_option', result.user.settings)

update session

						app.dao.updateColumn 'account', { id: result.user.id }, last_session: helper.nowUTCSeconds() / 1000

			express.get '/logout', (req, res) ->
				req.session.destroy()
				res.status(200).end()

			express.get '/status', (req, res) ->
				serverStatus = {}

get server version number:

				serverStatus['version'] = pkg.version

get rabbitmq connection status

				if app.bastion.isRabbitConnected()
					serverStatus['rabbitmq'] = 'connected'
				else
					serverStatus['rabbitmq'] = 'error'

get mongodb connection status

				if app.dao.getConnection().readyState
					serverStatus['mongodb'] = 'connected'
				else
					serverStatus['mongodb'] = 'error'
				res.status(200).send serverStatus

			express.all '*', (req, res, next) ->
				if req.method is 'OPTIONS'
					res.status(200).end()

API has no default/catchall renderer

				else if req.headers.host is CFG.domain_public
					next()
				else
					# try to find a default renderer for this domain
					app.modules.auth.domainAuth helper.getDomain(req.headers.host, true), (err, accountResult) ->
						if err
							res.status(500).end()
						else if !accountResult
							next()
						else
							# find default renderer
							ownerId = accountResult.getId()
							domain = accountResult.getActiveDomainObj()
							filter = null
							if app.helper.isObject(domain.renderer) and '' is not domain.renderer.channel_id
								filter =
									id: domain.renderer.channel_id
									owner_id: ownerId
								dao.find 'channel', filter, (err, result) ->
									if err
										res.status(500).end()
									else if !result
										res.status(404).end()
									else
										req.remoteUser = accountResult
										channelRender result.owner_id, result.id, domain.renderer.renderer, req, res
	}