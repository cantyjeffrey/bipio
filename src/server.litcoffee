## The Bipio API Server

Authors:

[Michael Pearson](https://github.com/mjpearson)  
[Alfonso Gober](https://github.com/alfonsogoberjr)  
[Scott Tuddenham](https://github.com/tuddman)  

Copyright (c) 2015 [Wot.io](https://wot.io)

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see [here](http://www.gnu.org/licenses/)

	bootstrap 				= require(__dirname + '/bootstrap')
	app 					= bootstrap.app
	cluster 				= require('cluster')
	express 				= require('express')
	restapi 				= express()
	http 					= require('http')
	https 					= require('https')
	session 				= require('express-session')
	cookieParser 			= require('cookie-parser')
	bodyParser 				= require('body-parser')
	jsonp 					= require('json-middleware')
	methodOverride 			= require('method-override')
	multer 					= require('multer')
	helper 					= require('./lib/helper')
	passport 				= require('passport')
	cron 					= require('cron')
	MongoStore 				= require('connect-mongo')(session: session)
	
Set global vars

	global.domain 			= require('domain')
	global.jwt 				= require('jsonwebtoken')
	global.pkg 				= require('../package.json')
	global.bipioVersion		= pkg.version

export app everywhere, like in [bootstrap.js](/bootstrap.js)

	module.exports.app = app

express bodyparser looks broken or too strict.

	xmlBodyParser = (req, res, next) ->
		enc = helper.getMime(req)
		if req._body
			return next()
		req.body = req.body or {}

ignore GET
		
		if 'GET' is req.method or 'HEAD' is req.method
			return next()

check Content-Type
	
		if !/xml/.test(enc)
			return next()

flag as parsed
		
		req._body = true

parse

		buf = ''
		req.setEncoding 'utf8'
		req.rawBody = ''
		req.on 'data', (chunk) ->
			req.rawBody += chunk

		req.on 'end', ->
			next()

	_jwtDeny = (res, extra) ->
		res.status(403).send 'Invalid X-JWT-Signature ' + (if extra then '- ' + extra else '')

if user has provided a jwt header, try to parse

	jwtConfirm = (req, res, next) ->
		masq = req.header('x-user-delegate')
		token = req.header('x-jwt-signature')
		structedMethods = [
			'POST'
			'PUT'
			'PATCH'
		]
		payload = {}

		if token
			if structedMethods.indexOf(req.method)
				payload = req.body
			try
				jwt.verify token, GLOBAL.CFG.jwtKey, (err, decoded) ->
				remoteHost = req.header('X-Forwarded-For') or req.connection.remoteAddress
				if err
					app.logmessage err.message + ' (IP ' + remoteHost + ')'
					_jwtDeny res, err.message
				else
					try
						if decoded.path is req.originalUrl # and JSON.stringify(decoded.body) is JSON.stringify(req.body))
							if decoded.user == masq
								req.masqUser = masq
								next()
							else
								_jwtDeny res
					catch e
						app.logmessage e.message, 'error'
						_jwtDeny res, e.message
			catch e

jsonwebtoken doesn't catch parse errors by itself.

				app.logmessage e.message, 'error'
				_jwtDeny res, e.message
		else
			next()

	setCORS = (req, res, next) ->
		res.header 'Access-Control-Allow-Origin', req.headers.origin
		res.header 'Access-Control-Allow-Headers', req.headers['access-control-request-headers'] or '*'
		res.header 'Access-Control-Allow-Methods', req.headers['access-control-request-method'] or 'GET,POST,PUT,DELETE'
		res.header 'Access-Control-Allow-Credentials', true
		next()

LOAD EXPRESS MIDDLEWARE

	restapi.use app.modules.cdn.utils.HTTPFormHandler()
	restapi.use xmlBodyParser
	restapi.use (err, req, res, next) ->
		if err.status == 400
			restapi.logmessage err, 'error'
			res.send err.status, message: 'Invalid JSON. ' + err
		else
			next err, req, res, next
	restapi.use bodyParser.urlencoded(extended: true)
	restapi.use bodyParser.json()
	restapi.use jwtConfirm
	restapi.use setCORS
	restapi.use methodOverride()
	restapi.use cookieParser()

required for some oauth providers

	restapi.use session(
		key: 'sid'
		resave: false
		saveUninitialized: true
		cookie:
			maxAge: 60 * 60 * 1000
			httpOnly: true
		secret: GLOBAL.CFG.server.sessionSecret
		store: new MongoStore(mongooseConnection: app.dao.getConnection()))
	restapi.use passport.initialize()
	restapi.use passport.session()
	restapi.set 'jsonp callback', true
	restapi.disable 'x-powered-by'
	

START CLUSTER

	if cluster.isMaster

when user hasn't explicitly configured a cluster size, use 1 process per cpu

		forks = if GLOBAL.CFG.server.forks then GLOBAL.CFG.server.forks else require('os').cpus().length
		app.logmessage 'BIPIO:STARTED:' + new Date
		app.logmessage 'Node v' + process.versions.node
		app.logmessage 'Starting ' + forks + ' fork(s)'
		i = 0
		while i < forks
			cluster.fork()
			i++
		app.dao.on 'ready', (dao) ->
			crons = GLOBAL.CFG.crons

Network chords and stats summaries

			if crons and crons.stat and '' is not crons.stat
				app.logmessage 'DAO:Starting Stats Cron', 'info'
				statsJob = new (cron.CronJob)(crons.stat, (->
					dao.generateHubStats (err, msg) ->
						if err
							app.logmessage 'STATS:THERE WERE ERRORS'
						else
							app.logmessage msg
							app.logmessage 'STATS:DONE'
				), null, true, GLOBAL.CFG.timezone)

periodic triggers

			if crons and crons.trigger and '' is not crons.trigger
				app.logmessage 'DAO:Starting Trigger Cron', 'info'
				triggerJob = new (cron.CronJob)(crons.trigger, (->
					dao.triggerAll (err, msg) ->
						if err
							app.logmessage 'TRIGGER:' + err + ' ' + msg
						else
							app.logmessage msg
							app.logmessage 'TRIGGER:DONE'
				), null, true, GLOBAL.CFG.timezone)

auto-expires

			if crons and crons.expire and '' is not crons.expire
				app.logmessage 'DAO:Starting Expiry Cron', 'info'
				expireJob = new (cron.CronJob)(crons.expire, (->
					dao.expireAll (err, msg) ->
						if err
							app.logmessage 'EXPIRE:ERROR:' + err
							app.logmessage msg
						else
							app.logmessage 'EXPIRE:DONE'
				), null, true, GLOBAL.CFG.timezone)
			
oAuth refresh
			
			app.logmessage 'DAO:Starting OAuth Refresh', 'info'
			oauthRefreshJob = new (cron.CronJob)('0 */15 * * * *', (->
				dao.refreshOAuth()
			), null, true, GLOBAL.CFG.timezone)

compile popular transforms into transform_defaults.

			if crons and crons.transforms_compact and '' is not crons.transforms_compact
				app.logmessage 'DAO:Starting Transform Compaction Cron', 'info'
				reduceTransformsJob = new (cron.CronJob)(crons.transforms_compact, (->
					bootstrap.app.dao.reduceTransformDefaults (err, msg) ->
						if err
							app.logmessage 'DAO:' + err + ' ' + msg
						else
							app.logmessage 'DAO:Transform Compaction:Done'
				), null, true, GLOBAL.CFG.timezone)

fetch scrubbed community transforms from upstream

			if GLOBAL.CFG.transforms and GLOBAL.CFG.transforms.fetch
				if crons and crons.transforms_fetch and '' is not crons.transforms_fetch
					app.logmessage 'DAO:Starting Transform Syncing Cron', 'info'
					syncTransformsJob = new (cron.CronJob)(crons.transforms_fetch, (->
						dao.updateTransformDefaults ->
							app.logmessage 'DAO:Syncing Transforms:Done'
					), null, true, GLOBAL.CFG.timezone)

		cluster.on 'disconnect', (worker) ->
			app.logmessage 'Worker:' + worker.workerID + ':Disconnect'
			cluster.fork()

	else
		workerId = cluster.worker.workerID
		app.logmessage 'BIPIO:STARTED:' + new Date
		helper.tldtools.init (->
			app.logmessage 'TLD:UP'
		), (body) ->
			app.logmessage 'TLD:Cache fail - ' + body, 'error'

		app.dao.on 'ready', (dao) ->
			server = undefined
			opts = {}
			if GLOBAL.CFG.server.ssl and GLOBAL.CFG.server.ssl.key and GLOBAL.CFG.server.ssl.cert
				app.logmessage 'BIPIO:SSL Mode'
				opts.key = fs.readFileSync(GLOBAL.CFG.server.ssl.key)
				opts.cert = fs.readFileSync(GLOBAL.CFG.server.ssl.cert)
			require('./router').init restapi, dao

			###
					restapi.use(function(err, req, res, next) {
							var rDomain = domain.create();

							res.on('close', function () {
								rDomain.dispose();
							});

							res.on('finish', function () {
								rDomain.dispose();
							});

							if (err) {
								app.logmessage(err, 'error');
								res.status(500);
								res.send({ error: 'Internal Error' });

								// respawn	worker
								if (!cluster.isMaster) {
									var killtimer = setTimeout(function() {
										app.logmessage('Worker:' + cluster.worker.workerID + ':EXITED');
										process.exit(1);
									}, 5000);

									killtimer.unref();

									app.bastion.close();
									server.close();
									cluster.worker.disconnect();
								}

								rDomain.dispose();

							} else {
								rDomain.run(next);
							}
						});
			###

			if opts.key
				server = https.createServer(opts, restapi)
			else
				server = http.createServer(restapi)
			server.listen GLOBAL.CFG.server.port, GLOBAL.CFG.server.host, ->
				rCache = require.cache
				for k of rCache
					if rCache.hasOwnProperty(k) and rCache[k].exports and rCache[k].exports.readme
						delete rCache[k].exports.readme
				app.logmessage 'Listening on :' + GLOBAL.CFG.server.port + ' in "' + restapi.settings.env + '" mode...'
