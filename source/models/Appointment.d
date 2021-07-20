module models.Appointment;

import std.datetime: SysTime;

import vibe.data.bson: BsonObjectID;

struct Appointment {
	BsonObjectID _id;
    BsonObjectID user_id;
	SysTime date;
}