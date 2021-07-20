import vibe.d;
import std.exception : enforce;
import vibe.core.log;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.http.server;
import vibe.utils.validation;
import vibe.web.auth;
import vibe.web.web;
import std.datetime: SysTime;
import std.typecons: Nullable;

import std.stdio: writeln;

import models.User: User;
import models.Appointment: Appointment;
import src.Constants;
import src.WebInterface: WebInterface, mongoClient;

shared static this() {
	mongoClient = connectMongoDB("0.0.0.0");
	auto admin = serializeToJson(User(BsonObjectID.generate(), "admin", "admin", "admin@gmail.com", true));

	try {
		auto users = mongoClient.getCollection(USERS_COLLECTION);
		users.insert(admin);
	} catch (Exception e) {
		writeln(e.msg);
	}

	auto router = new URLRouter;
	router.registerWebInterface(new WebInterface);

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["127.0.0.1"];
	settings.sessionStore = new MemorySessionStore;
	listenHTTP(settings, router);
}