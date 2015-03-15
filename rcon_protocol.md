# Introduction #

Talking to an Urban Terror server is not that difficult, but requires things to be done a certain way.

Most communication is just plain text.

All commands to the server must begin with four chars (4 bytes) of 255 (hex:FF) followed by the name of the command.

For example, to send the command 'test' to the server you would say:

> ### `[FF][FF][FF][FF]test\n` ###

where **`[ff]`** represents a single byte containing 255 and **`\n`** is a linefeed (ASCII character 12, hex: 0A ).


The response from the server is plain text, but is padded at the beginning of each packet with 4 bytes of 255 as well.

For example, sending the command:

> ### `[FF][FF][FF][FF]rcon\n` ###

without any password or other information will return this from the server:

> ### `[FF][FF][FF][FF]print\nBad rconpassword.\n` ###


Anything that can be done as an rcon command in game can also be done via this method as well.

This means that all the familiar commands work (status, kick, etc...)

# Blacklisted Characters #

The quake3 server does not allow any variable to contain:

`\ ; "`

# Commands #

Not all commands require rcon access.

The 'getstatus' command is what is used by sites like Gametracker and programs like Qtracker to retrieve information from a server.

In the table below `PW` is the rcon password.

| **Command** | **Info** | **Need Password** |
|:------------|:---------|:------------------|
| `getstatus` | Returns a basic list of players and the server config | No |
| `getinfo` | Returns a short description on the server (name, map, players..) | No |
| `getchallenge` | Returns an integer for a challenge response | No |
| `rcon PW status`  | Returns list of players and their information | Yes |
| `rcon PW serverinfo` | Returns a formatted list of the same information as `getstatus` | Yes |
| `rcon PW fdir *.bsp` | Returns list of all maps on the server | Yes |
| `rcon PW map <map name>` | Changes current map | Yes |
| `rcon PW kick <player name>` | Kicks the player with the matching name  | Yes |
| `rcon PW clientkick <player slot>` | Kicks the player in the given slot | Yes |
| `rcon PW addip <IP>` | Adds the given IP to the ban list | Yes |
| `rcon PW removeip <IP>` | Removes the given IP from the ban list | Yes |
| `rcon PW dumpuser <slot>` | Returns a formatted list of player infomation | Yes |
| `rcon PW echo TEXT`  | Echos back the TEXT to you | Yes |
| `rcon PW say TEXT`  | Prints the text at the bottom of the game screen 'console: TEXT' | Yes |
| `rcon PW cvarlist`  | Dumps out all of the cvars and their values | Yes |


# Shell Script #

If you are using a Linix/Unix/Solaris/BSD box then you can get the status of the server on the command line.

Rcon Status (password required)

```
printf '\xFF\xFF\xFF\xFFrcon <PASSWORD> status\n' | nc -u -n -w 1 <SERVER_IP> <SERVER_PORT> | sed -ne ':x;/\xFF/{N;s/\xFF\xFF\xFF\xFFprint\n//;tx};/^$/d;p'
```

Basic Status (no password required)

```
printf '\xFF\xFF\xFF\xFFgetstatus\n' | nc -u -n -w 1 <SERVER_IP> <SERVER_PORT>
```

(Replace `<PASSWORD>`, `<SERVER_IP>`, `<SERVER_PORT>` above with the actual values)



