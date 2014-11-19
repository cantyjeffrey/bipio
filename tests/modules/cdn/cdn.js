var fs = require('fs'),
	assert = require('assert'),
	should = require('should'),
	Fs_Cdn = require(__dirname + '/../../../src/modules/cdn/index.js'),
	config = require(__dirname + '/../../../config/default.json').modules.cdn.config,
	pkgcloud = require('pkgcloud'),
	async = require('async');

config.region = 'ORD';

var fs_cdn_remote = new Fs_Cdn(config),
	fs_cdn_local = new Fs_Cdn();


describe('fs-cdn', function() {
	it('prep', function(done) {
		fs_cdn_remote.save('test.png', __dirname + '/files/src/test.png', function(err, result) {
			if (err) throw new Error(err);
			done();
		});
	});

	describe('save', function() {

		it('should save test.png as test_save_string.png to CDN using path string', function(done) {
			fs_cdn_remote.save('test_save_string.png', __dirname + '/files/src/test.png', function(err, result) {
				if (err || !fs.existsSync(__dirname + '/files/src/test.png')) {
					throw new Error(err);
				}
				done();
			});
		});

		it('should save test.png as test_save_stream.png to CDN using a readable stream', function(done) {
			var readStream = fs.createReadStream(__dirname + '/files/src/test.png');

			fs_cdn_remote.save('test_save_stream.png', readStream, function(err, result) {
				if (err) {
					throw new Error(err);
				}
				done();
			});
		});

		it('should save src/test.png as test_save_string.png to file system using a path string', function(done) {
			fs_cdn_local.save(__dirname + '/files/dest/test_save_string.png', __dirname + '/files/src/test.png', function(err, result) {
				if (err) {
					throw new Error(err);
				}
				done();
			});
		});

		it('should save src/test.png as test_save_stream.png to file system using a readable stream', function(done) {
			var readStream = fs.createReadStream(__dirname + '/files/src/test.png');

			fs_cdn_local.save(__dirname + '/files/dest/test_save_stream.png', readStream, function(err, result) {
				if (err) {
					throw new Error(err);
				}
				done();
			});
		});

	});

	describe('get', function() {
		
		it('should get test.png as test_get_stream_remote.png from CDN using a writeable stream', function(done) {
			var writeStream = fs.createWriteStream(__dirname + '/files/dest/test_get_stream_remote.png');

			fs_cdn_remote.get('test.png', writeStream, function(err, result) {
				if (err) {
					throw new Error(err);
				}
				done();
			});
		});

		it('should get test.png as test_get_string_remote.png from CDN using a name string', function(done) {

			fs_cdn_remote.get('test.png', __dirname + '/files/dest/test_get_string_remote.png', function(err, result) {
				if (err) {
					throw new Error(err);
				}
				done();
			});
		});

		it('should get src/test.png as test_get_stream_local.png from file system using a writeable stream', function(done) {

			var writeStream = fs.createWriteStream(__dirname + '/files/dest/test_get_stream_local.png');

			fs_cdn_local.get(__dirname + '/files/src/test.png', writeStream, function(err, result) {
				if (err) {
					throw new Error(err);
				}
				done();
			});
		});

		it('should get src/test.png as test_get_string_local.png from file system using a name string', function(done) {

			fs_cdn_local.get(__dirname + '/files/src/test.png', __dirname + '/files/dest/test_get_string_local.png', function(err, result) {
				if (err) {
					throw new Error(err);
				}
				done();
			});
		});

	});

	describe('list', function() {

		it('should list all files in files/dest directory', function(done) {
			fs_cdn_local.list(__dirname + '/files/dest', function(err, result) {
				if (err) {
					throw new Error(err);
				}
				done();
			});
		});

		it('should list all files in container', function(done) {
			fs_cdn_remote.list(function(err, result) {
				if (err) {
					throw new Error(err);
				}
				done();
			});
		})

	});

	describe('remove', function() {

		it('should remove test files from CDN', function(done) {
			async.parallel({
				'test.png' : function(callback) {
								fs_cdn_remote.remove('test.png', 'bipio-beta-test', function(err, result) {
									if (err) {
										callback(err);
									}
									callback(null, result)
								})
							},
				'test_save_stream.png' : function(callback) {
								fs_cdn_remote.remove('test_save_stream.png', 'bipio-beta-test', function(err, result) {
									if (err) {
										callback(err);
									}
									callback(null, result)
								})
							},
				'test_save_string.png' : function(callback) {
								fs_cdn_remote.remove('test_save_string.png', 'bipio-beta-test', function(err, result) {
									if (err) {
										callback(err);
									}
									callback(null, result)
								})
							}
			}, function(err, results) {
				if (err) {
					throw new Error(err);
				}
				done();
			});
		});

		it('should remove test files from file system', function(done) {
			async.parallel({
				'test_save_stream.png' : function(callback) {
								fs_cdn_local.remove(__dirname + '/files/dest/test_save_stream.png', function(err, result) {
									if (err) {
										callback(err);
									}
									callback(null, result)
								})
							},
				'test_save_string.png' : function(callback) {
								fs_cdn_local.remove(__dirname + '/files/dest/test_save_string.png', function(err, result) {
									if (err) {
										callback(err);
									}
									callback(null, result)
								})
							},
				'test_get_stream_remote.png' : function(callback) {
								fs_cdn_local.remove(__dirname + '/files/dest/test_get_stream_remote.png', function(err, result) {
									if (err) {
										callback(err);
									}
									callback(null, result)
								})
							},
				'test_get_string_remote.png' : function(callback) {
								fs_cdn_local.remove(__dirname + '/files/dest/test_get_string_remote.png', function(err, result) {
									if (err) {
										callback(err);
									}
									callback(null, result)
								})
							},
				'test_get_stream_local.png' : function(callback) {
								fs_cdn_local.remove(__dirname + '/files/dest/test_get_stream_local.png', function(err, result) {
									if (err) {
										callback(err);
									}
									callback(null, result)
								})
							},
				'test_get_string_local.png' : function(callback) {
								fs_cdn_local.remove(__dirname + '/files/dest/test_get_string_local.png', function(err, result) {
									if (err) {
										callback(err);
									}
									callback(null, result)
								})
							}
			}, function(err, results) {
				if (err) {
					throw new Error(err);
				}
				done();
			});
		});

	});

});