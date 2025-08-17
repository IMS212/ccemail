package net.irisshaders.ccEmail;

import dan200.computercraft.api.ComputerCraftAPI;
import dan200.computercraft.api.lua.LuaException;
import dan200.computercraft.api.lua.LuaTable;
import dan200.computercraft.shared.computer.blocks.AbstractComputerBlockEntity;
import it.unimi.dsi.fastutil.ints.Int2ObjectMap;
import it.unimi.dsi.fastutil.ints.Int2ObjectOpenHashMap;
import it.unimi.dsi.fastutil.ints.IntArrayList;
import it.unimi.dsi.fastutil.ints.IntList;
import it.unimi.dsi.fastutil.objects.Object2ObjectMap;
import it.unimi.dsi.fastutil.objects.Object2ObjectOpenHashMap;
import net.fabricmc.api.ModInitializer;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;
import net.fabricmc.loader.api.FabricLoader;
import org.mapdb.*;

import java.util.ArrayList;
import java.util.Collection;
import java.util.List;

public class CcEmail implements ModInitializer {
    private static HTreeMap<Integer, String> emailAddresses;
    private static HTreeMap<String, Integer> emailAddressesRev;
    private static DB db;

    private static final IntList awake = new IntArrayList();

    private static final List<Runnable> mainThread = new ArrayList<>();

    private static final Int2ObjectMap<EmailComputer> computers = new Int2ObjectOpenHashMap<>();

    private static Int2ObjectMap<List<Email>> emails = new Int2ObjectOpenHashMap<>();
    private static Object2ObjectMap<String, List<String>> domains = new Object2ObjectOpenHashMap();
    private static Atomic.Integer emailId;

    public static void registerComputer(int id, EmailComputer emailComputer) {
        computers.put(id, emailComputer);
    }

    public static int getUser(String user) throws LuaException {
        int userId = emailAddressesRev.getOrDefault(user, -1);

        if (userId == -1) throw new LuaException("User not found: " + user);

        return userId;
    }

    public static long incrementEmailId() {
        return emailId.getAndIncrement();
    }

    public static void addEmail(Email email) {
        getEmails(email.getRecipientId()).add(email);
        db.commit();
        mainThread.add(() -> pushTo(email.getRecipientId()));
    }

    private static void pushTo(int recipientId) {
        EmailComputer ec = computers.get(recipientId);
        if (ec != null) {
            ((AbstractComputerBlockEntity) ec.getCurrentLevel().getBlockEntity(ec.getCurrentPos())).createServerComputer().queueEvent("email_received");
        }
    }

    public static void setUsername(int id, String username) throws LuaException {
        String[] parts = username.split("@");
        if (parts.length != 2) throw new LuaException("Invalid email address: " + username + " (must be in the form user@base)");
        emailAddresses.put(id, username);
        emailAddressesRev.put(username, id);
        getDomain(parts[1]).add(parts[0]);
        db.commit();
    }

    public static List<String> getDomain(String part) {
        return domains.computeIfAbsent(part, i -> {
            List<String> l = db.indexTreeList("domain_" + i, Serializer.STRING).createOrOpen();
            db.commit();
            return l;
        });
    }

    public static boolean hasUsername(int id) {
        return emailAddresses.containsKey(id);
    }

    public static String getNameFor(int id) {
        return emailAddresses.getOrDefault(id, "<unknown>");
    }

    public static void markAwake(int id) {
        awake.add(id);
    }

    public static Collection<String> getAllUsers() {
        return emailAddresses.values();
    }

    @Override
    public void onInitialize() {
        db = DBMaker.fileDB(FabricLoader.getInstance().getGameDir().resolve("email.db").toFile())
                .closeOnJvmShutdown().fileMmapEnable().transactionEnable().make();

        emailAddresses = db.hashMap("emailAddresses", Serializer.INTEGER, Serializer.STRING).createOrOpen();
        emailAddressesRev = db.hashMap("emailAddressesRev", Serializer.STRING, Serializer.INTEGER).createOrOpen();

        emailId = db.atomicInteger("emailId").createOrOpen();

        ComputerCraftAPI.registerAPIFactory(new EmailComputer.Creator());

        ServerTickEvents.END_SERVER_TICK.register((e) -> {
            for (Runnable r : mainThread) {
                r.run();
            }
            awake.forEach(i -> {
                if (getEmails(i).stream().anyMatch(es -> !es.hasRead())) {
                    pushTo(i);
                }
            });
            awake.clear();
            mainThread.clear();
        });
    }

    public static List<Email> getEmails(int user) {
        return emails.computeIfAbsent(user, i -> {
            List<Email> l = db.indexTreeList("inbox_" + i, Email.SERIALIZER).createOrOpen();
            db.commit();
            return l;
        });
    }
}


