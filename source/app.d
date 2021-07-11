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

MongoClient mongoClient;

enum APPOINTMENTS_COLLECTION = "tutorial.appointments";
enum USERS_COLLECTION = "tutorial.users";

struct Appointment {
	BsonObjectID user_id;
	SysTime date;
}

struct User {
	BsonObjectID id;
	string name;
	string password;
	string email;

	bool admin;

	@safe:
	bool isAdmin() { return this.admin; }
}

Appointment[][int] _appointments;

auto _users = User[].init; 


@requiresAuth
class Rest {

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
		string postLogin(string user, string password, scope HTTPServerRequest req, scope HTTPServerResponse res) @safe {
			enforce(user == "John Terry" && password == "parola", "greseala");

			User u = _users[0];
			req.session = res.startSession;
			req.session.set("auth", u);

			return "logged";
		}

		string getRegister(string _error = null) {
			return _error;
		}

		@errorDisplay!getRegister
		void postRegister(string username, string password, string email, scope HTTPServerResponse res) @safe {
			//enforceHTTP(username && password);

			auto users = mongoClient.getCollection(USERS_COLLECTION);
			User newUser = User(BsonObjectID.generate(), username, password, email, false);
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
			auto results = appointments.find(["user_id": _user.id]).map!(a => a.toJson()).array;

			res.writeJsonBody!(Json[])(results, "application/json");
		}

		void createAppointments(scope HTTPServerResponse res, SysTime date, User _user) @safe {			
			auto appointments = mongoClient.getCollection(APPOINTMENTS_COLLECTION);
			try {
				appointments.insert(serializeToBson(Appointment(_user.id, date)));
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
				appointments.update(["user_id": _user.id, "_id": _id], ["$set": ["date": date]]);
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
				appointments.remove(["user_id": _user.id, "_id": _id]);
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
			Appointment[] allAppointments = Appointment[].init;
			foreach (id, appointments; _appointments) {
				allAppointments ~= appointments;
			}

			res.writeJsonBody!(Appointment[])(allAppointments);
		}

		@path("/users")
		@method(HTTPMethod.GET)
		void listAllUsers(scope HTTPServerResponse res) @safe {
			res.writeJsonBody!(User[])(_users);
		}
	}
}

shared static this() {
	mongoClient = connectMongoDB("0.0.0.0");
	auto users = mongoClient.getCollection("tutorial.users");

	_users = [
		User(BsonObjectID.generate(), "John Terry", "parola", "johnterry@chelsea.com", true),
		User(BsonObjectID.generate(), "Gica Hagi", "parola", "ainaimingea@dailapoarta.com", false)
	];

	auto terry = serializeToJson(_users[0]);

	//users.insert(terry);

	// import std.stdio: writeln;
	// import std.typecons: Nullable;
	// Nullable!User user = users.findOne!User(["id": 1]);

	// if (!user.isNull()) {
	// 	writeln("User: ", user.get.name);
	// }

	// writeln(users.find());

	auto router = new URLRouter;

	router.registerWebInterface(new Rest);

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["127.0.0.1"];
	settings.sessionStore = new MemorySessionStore;
	listenHTTP(settings, router);
}