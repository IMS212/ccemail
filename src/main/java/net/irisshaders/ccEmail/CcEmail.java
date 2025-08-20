package net.irisshaders.ccEmail;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.StringArgumentType;
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
import net.fabricmc.fabric.api.command.v2.CommandRegistrationCallback;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;
import net.fabricmc.loader.api.FabricLoader;
import net.minecraft.commands.CommandBuildContext;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.Component;
import org.mapdb.*;

import java.util.*;

public class CcEmail implements ModInitializer {
    private static HTreeMap<Integer, String> emailAddresses;
    private static Set<String> users;
    private static HTreeMap<String, Integer> emailAddressesRev;
    private static DB db;

    private static final IntList awake = new IntArrayList();

    private static final List<Runnable> mainThread = new ArrayList<>();

    private static final Int2ObjectMap<EmailComputer> computers = new Int2ObjectOpenHashMap<>();

    private static Int2ObjectMap<List<Email>> emails = new Int2ObjectOpenHashMap<>();
    private static Object2ObjectMap<String, List<String>> domains = new Object2ObjectOpenHashMap();
    private static Atomic.Integer emailId;
    private static String[] cachedUsersSorted;

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
        String oldName = emailAddresses.put(id, username);
        if (oldName != null) {
            String[] parts2 = oldName.split("@");

            emailAddressesRev.remove(oldName);
            users.remove(oldName);
            getDomain(parts2[1]).remove(parts2[0]);
        }
        emailAddressesRev.put(username, id);
        users.add(username);
        getDomain(parts[1]).add(parts[0]);
        db.commit();
        calculateCache();
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
            return emailAddresses.getOrDefault(id, null);
    }

    public static void markAwake(int id) {
        awake.add(id);
    }

    public static Set<String> getAllUsers() {
        return users;
    }

    public static void commitDB() {
        db.commit();
    }

    public static boolean usernameValid(String name) {
        return name.contains("global") || emailAddressesRev.containsKey(name);
    }

    public static String[] getCachedUserSorted() {
        if (cachedUsersSorted == null) {
            calculateCache();
        }
        return cachedUsersSorted;
    }

    private static final Comparator<? super String> SORT_DOMAIN = (o1, o2) -> {
        String o1Domain = o1.split("@")[1];
        String o2Domain = o2.split("@")[1];
        int domainComparison = o1Domain.compareTo(o2Domain);

        if (domainComparison != 0) {
            return domainComparison;
        }

        String o1Name = o1.split("@")[0];
        String o2Name = o2.split("@")[0];
        return o1Name.compareTo(o2Name);
    };

    private static void calculateCache() {
        cachedUsersSorted = getAllUsers().stream().sorted(SORT_DOMAIN).toArray(String[]::new);
    }

    @Override
    public void onInitialize() {
        CommandRegistrationCallback.EVENT.register(this::registerCommands);
        db = DBMaker.fileDB(FabricLoader.getInstance().getGameDir().resolve("email.db").toFile())
                .closeOnJvmShutdown().fileMmapEnable().transactionEnable().make();

        emailAddresses = db.hashMap("emailAddresses", Serializer.INTEGER, Serializer.STRING).createOrOpen();
        users = db.hashSet("userSet", Serializer.STRING).createOrOpen();
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

    private void registerCommands(CommandDispatcher<CommandSourceStack> commandSourceStackCommandDispatcher, CommandBuildContext commandBuildContext, Commands.CommandSelection commandSelection) {
        commandSourceStackCommandDispatcher.register(Commands.literal("ccemail").then(Commands.literal("resetUserStack").requires(c -> c.hasPermission(2)).executes(context -> {
            users.clear();
            users.addAll(emailAddressesRev.keySet());
            commitDB();
            System.out.println("[CC Email] Reset the user stack; users:");
            for (String user : users) {
                System.out.println(" - " + user);
            }
            return 1;
        }))
                .then(Commands.literal("alias").then(Commands.argument("user", StringArgumentType.string()).then(Commands.argument("alias", StringArgumentType.string()).executes(context -> {
                    String user = StringArgumentType.getString(context, "user");
                    String alias = StringArgumentType.getString(context, "alias");
                    try {
                        emailAddressesRev.put(alias, getUser(user));
                        context.getSource().sendSuccess(() -> Component.literal("Successfully aliased " + user + " to " + alias), false);
                    } catch (LuaException e) {
                        context.getSource().sendFailure(Component.literal("Failed; user likely doesn't exist"));
                        return 0;
                    }
                    return 1;
                })))).then(Commands.literal("delete").requires(i -> i.hasPermission(2)).then(Commands.argument("account", StringArgumentType.string()).executes(context -> {
                    try {
                        int userId = emailAddressesRev.getOrDefault(StringArgumentType.getString(context, "account"), -1);
                        if (userId == -1) {
                            context.getSource().sendFailure(Component.literal("User not found"));
                            return 0;
                        }
                        String name = StringArgumentType.getString(context, "account");
                        emailAddresses.remove(userId);
                        emailAddressesRev.entrySet().removeIf(entry -> entry.getValue() == userId);
                        if (emails.containsKey(userId)) {
                            emails.remove(userId);
                        }
                        getDomain(name.split("@")[1]).remove(name.split("@")[0]);
                        commitDB();
                    } catch (Exception e) {
                        e.printStackTrace();
                        context.getSource().sendFailure(Component.literal("Failed to delete account: " + e.getMessage()));
                        return 0;
                    }
                    return 1;
                }))));;
    }

    public static List<Email> getEmails(int user) {

        return emails.computeIfAbsent(user, i -> {
            List<Email> l = db.indexTreeList("inbox_" + i, Email.SERIALIZER).createOrOpen();
            db.commit();
            return l;
        });
    }
}


