package net.irisshaders.ccEmail;

import dan200.computercraft.api.lua.LuaFunction;
import org.mapdb.DataInput2;
import org.mapdb.DataOutput2;
import org.mapdb.Serializer;

import java.io.IOException;
import java.util.Objects;

public class Email {
    public static final Serializer<Email> SERIALIZER = new Serializer<Email>() {
        @Override
        public void serialize(DataOutput2 out, Email value) throws IOException {
            out.writeLong(value.id);
            out.writeInt(value.senderId);
            out.writeInt(value.recipientId);
            out.writeUTF(value.subject != null ? value.subject : "");
            out.writeUTF(value.body != null ? value.body : "");
            out.writeLong(value.timestamp);
            out.writeBoolean(value.hasRead);
        }

        @Override
        public Email deserialize(DataInput2 input, int available) throws IOException {
            long id = input.readLong();
            int senderId = input.readInt();
            int recipientId = input.readInt();
            String subject = input.readUTF();
            String body = input.readUTF();
            long ts = input.readLong();
            boolean hasRead = input.readBoolean();
            return new Email(id, senderId, recipientId, subject, body, ts, hasRead);
        }
    };
    private final long id;
    private final int senderId;
    private final int recipientId;
    private final String subject;
    private final String body;
    private final long timestamp;
    private boolean hasRead = false;

    public Email(long id, int senderId, int recipientId, String subject, String body, long timestamp, boolean hasRead) {
        this.id = id;
        this.senderId = senderId;
        this.recipientId = recipientId;
        this.subject = subject;
        this.body = body;
        this.timestamp = timestamp;
        this.hasRead = hasRead;
    }

    @LuaFunction("getEmailId")
    public final long getId() {
        return id;
    }

    @LuaFunction("getSender")
    public final int getSenderId() {
        return senderId;
    }

    @LuaFunction("getRecipient")
    public final int getRecipientId() {
        return recipientId;
    }

    @LuaFunction("getSubject")
    public final String getSubject() {
        return subject;
    }

    @LuaFunction("getBody")
    public final String getBody() {
        return body;
    }

    @LuaFunction("getTimestamp")
    public final long getTimestamp() {
        return timestamp;
    }

    @LuaFunction("hasRead")
    public final boolean hasRead() {
        return hasRead;
    }

    @LuaFunction("markRead")
    public final void markRead() {
        hasRead = true;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Email email = (Email) o;
        return id == email.id;
    }

    @Override
    public int hashCode() {
        return Objects.hash(id);
    }

    @Override
    public String toString() {
        return "Email{" +
                "id=" + id +
                ", senderId=" + senderId +
                ", recipientId=" + recipientId +
                ", subject='" + subject + '\'' +
                ", timestamp=" + timestamp +
                '}';
    }
}

