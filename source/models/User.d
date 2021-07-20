module models.User;

import vibe.data.bson: BsonObjectID;

struct User {
	BsonObjectID _id;
	string name;
	string password;
	string email;

	bool admin;

	@safe:
	bool isAdmin() { return this.admin; }
}