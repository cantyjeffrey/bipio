//rackspace.js

//Extend and override fs strategy to use Rackspace Cloudfiles CDN
//Functionality in lib/cdn.js is mirrored here
//Functionality in bip-pod/index.js mirrored here

/*****************************************************************************************************
*                                                                                                    *
* cloudfiles.js                                                                                      *
* -----------------------                                                                            *
* a Bipio wrapper for the Rackspace CloudFiles API, supplied by pkgcloud                             *
*                                                                                                    *
* For docs, see https://github.com/pkgcloud/pkgcloud/blob/master/docs/providers/rackspace/storage.md *
*                                                                                                    *
******************************************************************************************************/

var FileStorage = require('./prototype.js') 
var pkgcloud = require('pkgcloud');

var client = pkgcloud.storage.createClient({
	"provider" : GLOBAL.CFG.cdn.provider,
	"username" : GLOBAL.CFG.cdn.config.username,
	"apiKey": GLOBAL.CFG.cdn.config.apiKey
});

var callClient = function() {
	if (arguments.length >= 2 && typeof arguments[arguments.length-1] === 'function') {
		var callback = arguments[arguments.length-1]
		if (arguments.length === 4) {
			client[arguments[0]](arguments[1], arguments[2], function(err, result) {
				if (err) console.log(err);
				else callback(err, result);
			});
		}
		else {
			client[arguments[0]](arguments[1], function(err, result) {
				if (err) console.log(err);
				else callback(err, result);
			});
		}
	};
};

var cloudFiles = Object.create(FileStorage);

cloudFiles.container = {
	create: function(name, callback) {
		var options = {
				name: name,
				metadata: {
					hostname: process.env.BIPIO_HOSTNAME,
					timestamp: Date.now()
				}
			};
		callClient('createContainer', options, callback);
	},

	get: function() {
		if (typeof arguments[0] === 'function') callClient('getContainers', arguments[0]);
		else callClient('getContainer', arguments[0], arguments[1]);
	},

	destroy: function(name, callback) {
		callClient('destroyContainer', name, callback);
	},

	find: function(name, callback) {
		client.getContainer(name, function(err, container){
			if (err) {
				client.getContainers(name, function(err, containers) {
					for (var i in containers) {
						if (containers[i].name === name) callback(null, containers[i]);
					}
				}) 
			}
			else callback(null, container);
		});
	},

	metadata: {
		update: function(name, callback) {
			//needs a bit of research before encapsulation
		},

		remove: function(name, obj, callback) {
			callClient('removeContainerMetadata', name, obj, callback);
		}
	}
};

cloudFiles.file = {
	upload: function(options, callback) {
		callClient('upload', options, callback);
	},

	download: function(options, callback) {
		callClient('download', options, callback);
	},

	get: function(container, options, callback) {
		var method;
		if (typeof options === 'string') method = 'getFile';
		else if (typeof options === 'object') method = 'getFiles';
		callClient(method, container, options, callback);
	},

	remove: function(container, file, callback) {
		callClient('removeFile', container, file, callback);
	},

	find: function(container, file, callback) {
		client.getFile(container, file, function(err, file){
			if (err) {
				client.getFiles(container, {}, function(err, files) {
					for (var i in files) {
						if (files[i].name === name) callback(null, files[i]);
					}
				}) 
			}
			else callback(null, file);
		});
	},

	metadata: {
		update: function(container, file, callback) {
			callClient('updateFileMetadata', container, file, callback);
		}
	}
};

cloudFiles.httpStream = function(url, outFile, cb, exports, fileStruct) {
	var self = this;
	var tmpFileName = outFile.split("/")[outFile.split("/").length - 1]
	var account = outFile.split("/")[6];
	app.logmessage("account = " + account + "\noutFile = " + outFile + "\ntmpFileName = " + tmpFileName);

	//check for existence of file on FS
	fs.exists(outFile, function(exists) {
	  //if file exists on FS
		if (exists) {
		//check for container's existence on CDN
			self.container.find(account, function(err, container){
			//if container exists
				if (container) {
				//check for file existence in container
					self.file.find(container.name, tmpFileName, function(err, file){
					//if file exists
						if (file) {
							//move on
							fs.stat(outFile, function(err, stats) {
								if (err) {
									app.logmessage(err, 'error');
									next(true);
								} 
								else {
									app.logmessage( self._name + ' CACHED, skipping [' + outFile + ']');
									fileStruct.size = stats.size;
									cb(false, exports, fileStruct);
								}
							});
						}
						//if file doesn't exist
						if (err) {
							//upload file
							self.uploadToCDN(url, outFile, cb, container.name, tmpFileName, self);
						}
					});
				}
				//if container doesn't exist
				if (err) {
					//create container
					self.container.create(account, function(err, container) {
						if (container) {
							//upload file
							app.logmessage(self._name + ' created container ' + container.name)
							self.uploadToCDN(url, outFile, cb, container.name, tmpFileName, self);
				 		}
					});
				}
			});
		}
		//if file doesnt exist on FS
		else {
			//download file to FS
			app.logmessage( self._name + ' creating local file ' + outFile);
			var writeStream = fs.createWriteStream(outFile);
			request.get(url).pipe(writeStream)
			writeStream.on('close', function() {
				app.logmessage(self._name + ' finished local download of ' + tmpFileName);
				cb(false, exports, fileStruct);
			});
		}
	});
};

cloudFiles.uploadToCDN = function(url, outFile, cb, containerName, tmpFileName, self) {
	self.file.upload({
		container: containerName,
		remote: tmpFileName,
		local: outFile
	}, function(err, result) {
		if (result) {
			app.logmessage(self._name + ' finished uploading ' + tmpFileName + ' to CloudFiles container ' + containerName);
			cb(false, exports, fileStruct);
		}
		if (err) {
			next(err);
		}
	});
};


module.exports = cloudFiles;
