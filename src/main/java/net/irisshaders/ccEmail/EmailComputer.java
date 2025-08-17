package net.irisshaders.ccEmail;

import dan200.computercraft.api.lua.*;
import dan200.computercraft.shared.computer.core.ServerComputer;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import org.jspecify.annotations.Nullable;

import java.util.List;

public class EmailComputer implements ILuaAPI {
    private final int id;
    private final IComputerSystem system;

    public EmailComputer(IComputerSystem iComputerSystem) {
        this.id = iComputerSystem.getID();
        this.system = iComputerSystem;

        CcEmail.registerComputer(this.id, this);
    }

    @Override
    public String[] getNames() {
        return new String[] { "winter_email" };
    }

    @Override
    public @Nullable String getModuleName() {
        return null;
    }

    public BlockPos getCurrentPos() {
        return system.getPosition();
    }

    @LuaFunction("getEmails")
    public final int getEmails() {
        return CcEmail.getEmails(this.id).size();
    }

    @LuaFunction("getEmail")
    public final Email getEmail(int index) throws LuaException {
        List<Email> list = CcEmail.getEmails(this.id);
        if (index < 0 || index >= list.size()) {
            throw new LuaException("Index out of bounds: " + index);
        }
        return list.get(index);
    }

    @LuaFunction("deleteEmail")
    public final void deleteEmail(int index) {
        CcEmail.getEmails(this.id).remove(index);
    }

    @LuaFunction("sendEmail")
    public final void sendEmail(String user, String subject, String body) throws LuaException {
        String[] parts = user.split("@");

        if (parts[0].equalsIgnoreCase("global")) {
            if (parts[1].equalsIgnoreCase("global")) {
                for (String i : CcEmail.getAllUsers()) {
                    int recipientId = CcEmail.getUser(i);

                    Email email = new Email(CcEmail.incrementEmailId(), this.id, recipientId, subject, body, System.currentTimeMillis(), false);

                    CcEmail.addEmail(email);
                }
            } else {
                for (String i : CcEmail.getDomain(parts[1])) {
                    int recipientId = CcEmail.getUser(i + "@" + parts[1]);

                    Email email = new Email(CcEmail.incrementEmailId(), this.id, recipientId, subject, body, System.currentTimeMillis(), false);

                    CcEmail.addEmail(email);
                }
            }
        } else {
        int recipientId = CcEmail.getUser(user);

        Email email = new Email(CcEmail.incrementEmailId(), this.id, recipientId, subject, body, System.currentTimeMillis(), false);

        CcEmail.addEmail(email);
        }
    }

    @LuaFunction
    public final void setUsername(String username) throws LuaException {
        CcEmail.setUsername(id, username);
    }

    @LuaFunction
    public final String getNameFor(int id) {
        return CcEmail.getNameFor(id);
    }

    @LuaFunction
    public final boolean hasUsername() {
        return CcEmail.hasUsername(id);
    }

    @LuaFunction
    public final String getUsername() {
        return CcEmail.getNameFor(id);
    }

    public ServerLevel getCurrentLevel() {
        return system.getLevel();
    }

    @Override
    public void update() {

    }

    @Override
    public void startup() {
        CcEmail.markAwake(id);
    }

    public static class Creator implements ILuaAPIFactory {
        @Override
        public @Nullable ILuaAPI create(IComputerSystem iComputerSystem) {
            return new EmailComputer(iComputerSystem);
        }
    }
}
