module src.WebInterface;

import std.datetime: SysTime;
import std.typecons: Nullable;

import vibe.db.mongo.mongo;
import vibe.web.auth;
import vibe.web.web: errorDisplay, terminateSession;
import vibe.web.common: noRoute, path, method;
import vibe.http.server: HTTPServerResponse, HTTPServerRequest, HTTPStatus, HTTPMethod, HTTPStatusException;

import src.Constants;
import models.User: User;
import models.Appointment: Appointment;

MongoClient mongoClient;

@requiresAuth
class WebInterface {

	@noRoute
	User authenticate(scope HTTPServerRequest req, scope HTTPServerResponse res) @safe {
		if (!req.session || !req.session.isKeySet("auth"))
			throw new HTTPStatusException(HTTPStatus.forbidden, "Not authorized to perform this action!");

		return req.session.get!User("auth");
	}

	@noAuth {
		@path("/") string getHome(scope HTTPServerRequest req) @safe {
			Nullable!User auth;
			if (req.session && req.session.isKeySet("auth"))
				auth = req.session.get!User("auth");

			return auth.isNull ? "" : auth.get().name;
		}

		string getLogin(string _error = null) {
			return _error;
		}

		@errorDisplay!getLogin
		void postLogin(string email, string password, scope HTTPServerRequest req, scope HTTPServerResponse res) @safe {
            if (req.session && req.session.isKeySet("auth")) {
                throw new HTTPStatusException(HTTPStatus.forbidden, "Not authorized to perform this action!");
            }

			try {
				auto usersCollection = mongoClient.getCollection(USERS_COLLECTION);
                auto users = usersCollection.find(["email": email, "password": password]);
                if (users.empty) {
                    throw new HTTPStatusException(HTTPStatus.NotFound, "User does not exist.");
                }

                auto user = users.front.toJson.deserializeJson!User;

				req.session = res.startSession;
				req.session.set("auth", user);
				res.writeJsonBody!string(user.email);
			} catch (Exception e) {
				res.writeJsonBody!string(e.msg, HTTPStatus.NotFound);
			}
		}

		string getRegister(string _error = null) {
			return _error;
		}

		@errorDisplay!getRegister
		void postRegister(string name, string password, string email, scope HTTPServerRequest req, scope HTTPServerResponse res) @safe {
            if (req.session && req.session.isKeySet("auth")) {
                throw new HTTPStatusException(HTTPStatus.forbidden, "Not authorized to perform this action!");
            }

			auto users = mongoClient.getCollection(USERS_COLLECTION);
			User newUser = User(BsonObjectID.generate(), name, password, email, false);
			try {
				users.insert(serializeToBson(newUser));
			} catch(Exception e) {
				res.writeJsonBody!(string)(e.msg, HTTPStatus.Conflict);
				return;
			}

			res.writeJsonBody!User(newUser, HTTPStatus.OK);
		}
	}

	@anyAuth {
		void getAppointments(scope HTTPServerResponse res, User _user) @safe {
			import std.algorithm: map;
			import std.array;
			auto appointments = mongoClient.getCollection(APPOINTMENTS_COLLECTION);
			auto results = appointments.find(["user_id": _user._id])
                                       .map!(a => a.toJson.deserializeJson!Appointment)
                                       .array;

			res.writeJsonBody!(Appointment[])(results);
		}

		void createAppointments(scope HTTPServerResponse res, SysTime date, User _user) @safe {			
			auto appointments = mongoClient.getCollection(APPOINTMENTS_COLLECTION);
			try {
				appointments.insert(serializeToBson(Appointment(BsonObjectID.generate(), _user._id, date)));
			} catch(Exception e) { 
				res.writeJsonBody!(string)(e.msg, HTTPStatus.Conflict);
				return;
			}

			res.writeJsonBody!string("Appointment created.", HTTPStatus.OK);
		}

		@path("/appointments/:id")
		@method(HTTPMethod.PUT)
		void modifyAppointment(scope HTTPServerResponse res, User _user, BsonObjectID _id, SysTime date) @safe {
			auto appointments = mongoClient.getCollection(APPOINTMENTS_COLLECTION);
			try {
				appointments.update(["user_id": _user._id, "_id": _id], ["$set": ["date": date]]);
			} catch(Exception e) {
				res.writeJsonBody!(string)(e.msg, HTTPStatus.NotFound);
				return;
			}

			res.writeJsonBody!(string)("Appointment modified.", HTTPStatus.OK);
		}

		@path("/appointments/:id")
		@method(HTTPMethod.DELETE)
		void cancelAppointments(scope HTTPServerResponse res, User _user, BsonObjectID _id) @safe {
			auto appointments = mongoClient.getCollection(APPOINTMENTS_COLLECTION);
			try {
				appointments.remove(["user_id": _user._id, "_id": _id]);
			} catch (Exception e) {
				res.writeJsonBody!(string)(e.msg, HTTPStatus.NotFound);
				return;
			}

			res.writeJsonBody!(string)("Appointment canceled.", HTTPStatus.OK);
		}

		void postLogout(scope HTTPServerResponse res) @safe {
			terminateSession();
			res.writeJsonBody!string("logged out");
		}
	}

	@auth(Role.admin) {
		@path("/appointments/all")
		@method(HTTPMethod.GET)
		void listAllAppointments(scope HTTPServerResponse res) @safe {
			try {
				import std.algorithm: map;
				import std.array;
				auto appointments = mongoClient.getCollection(APPOINTMENTS_COLLECTION);
				auto results = appointments.find()
                                           .map!(a => a.toJson.deserializeJson!Appointment)
                                           .array;

				res.writeJsonBody!(Appointment[])(results);
			} catch (Exception e) {
				res.writeJsonBody!string(e.msg, HTTPStatus.NotFound);
			}
		}

		@path("/users")
		@method(HTTPMethod.GET)
		void listAllUsers(scope HTTPServerResponse res) @safe {
			try {
				import std.algorithm: map;
				import std.array;
				auto users = mongoClient.getCollection(USERS_COLLECTION);
				auto results = users.find()
                                    .map!(a => a.toJson.deserializeJson!User)
                                    .array;

				res.writeJsonBody!(User[])(results);
			} catch (Exception e) {
				res.writeJsonBody!string(e.msg, HTTPStatus.NotFound);
			}
		}
	}
}