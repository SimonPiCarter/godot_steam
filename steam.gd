extends Node


const PACKET_READ_LIMIT: int = 32
var STEAM_ID: int = 0
var STEAM_USERNAME: String = ""
var LOBBY_ID: int = 0
var LOBBY_MEMBERS: Array = []
var LOBBY_VOTE_KICK: bool = false
var LOBBY_MAX_MEMBERS: int = 10

# emited on every data received
signal handle_data(data)

# emited when lobby list is updated (array of dictionnary)
signal lobby_list_update(lobbies)

# signal when lobby is joined
signal lobby_joined()

# signal when lobby is updated
signal lobby_update()

# Called when the node enters the scene tree for the first time.
func _ready():
	_initialize_Steam()
	print(Steam.isSteamRunning())

	var _IS_ONLINE: bool = Steam.loggedOn()
	var _STEAM_ID: int = Steam.getSteamID()
	var IS_OWNED: bool = Steam.isSubscribed()

	print(STEAM_ID," : ", IS_OWNED)

	Steam.lobby_created.connect(_on_Lobby_Created)
	Steam.lobby_match_list.connect(_on_Lobby_Match_List)
	Steam.lobby_joined.connect(_on_Lobby_Joined)
	Steam.lobby_chat_update.connect(_on_Lobby_Chat_Update)
	#Steam.lobby_message.connect(_on_Lobby_Message)
	#Steam.lobby_data_update.connect(_on_Lobby_Data_Update)
	#Steam.lobby_invite.connect(_on_Lobby_Invite)
	Steam.join_requested.connect(_on_Lobby_Join_Requested)
	Steam.persona_state_change.connect(_on_Persona_Change)

	# Check for command line arguments
	_check_Command_Line()

func _initialize_Steam() -> void:
	var INIT: Dictionary = Steam.steamInit()
	print("Did Steam initialize?: "+str(INIT))

	if INIT['status'] != 1:
		print("Failed to initialize Steam. "+str(INIT['verbal'])+" Shutting down...")
		get_tree().quit()

func _create_Lobby() -> void:
	# Make sure a lobby is not already set
	if LOBBY_ID == 0:
		Steam.createLobby(Steam.LobbyType.LOBBY_TYPE_PUBLIC, LOBBY_MAX_MEMBERS)
		print("Trying to create a lobby")

func _on_Lobby_Created(connect_id: int, lobby_id: int) -> void:
	print("Created a lobby: "+str(lobby_id))
	if connect_id == 1:
		# Set the lobby ID
		LOBBY_ID = lobby_id
		print("Created a lobby: "+str(LOBBY_ID))

		# Set this lobby as joinable, just in case, though this should be done by default
		Steam.setLobbyJoinable(LOBBY_ID, true)

		# Set some lobby data
		Steam.setLobbyData(lobby_id, "name", "Gramps' Lobby")
		Steam.setLobbyData(lobby_id, "mode", "GodotSteam test")

		# Allow P2P connections to fallback to being relayed through Steam if needed
		var RELAY: bool = Steam.allowP2PPacketRelay(true)
		print("Allowing Steam to be relay backup: "+str(RELAY))

func _lock_lobby() -> void:
	if LOBBY_ID != 0:
		Steam.setLobbyJoinable(LOBBY_ID, false)

func _process(_delta):
	Steam.run_callbacks()

	if LOBBY_ID > 0:
		_read_All_P2P_Packets()

func _read_All_P2P_Packets(read_count: int = 0):
	if read_count >= PACKET_READ_LIMIT:
		return
	if Steam.getAvailableP2PPacketSize(0) > 0:
		_read_P2P_Packet()
		_read_All_P2P_Packets(read_count + 1)

func _read_P2P_Packet() -> void:
	var PACKET_SIZE: int = Steam.getAvailableP2PPacketSize(0)

	# There is a packet
	if PACKET_SIZE > 0:
		var pack: Dictionary = Steam.readP2PPacket(PACKET_SIZE, 0)

		if pack.size() == 0 or pack == null:
			print("WARNING: read an empty packet with non-zero size!")

		# Get the remote user's ID
		var _PACKET_SENDER: int = pack['steam_id_remote']

		# Make the packet data readable
		var PACKET_CODE: PackedByteArray = pack['data']
		var READABLE: Dictionary = bytes_to_var(PACKET_CODE)

		# Append logic here to deal with packet data
		handle_data.emit(READABLE)

func _check_Command_Line() -> void:
	var ARGUMENTS: Array = OS.get_cmdline_args()

	# There are arguments to process
	if ARGUMENTS.size() > 0:

		# A Steam connection argument exists
		if ARGUMENTS[0] == "+connect_lobby":

			# Lobby invite exists so try to connect to it
			if int(ARGUMENTS[1]) > 0:

				# At this point, you'll probably want to change scenes
				# Something like a loading into lobby screen
				print("CMD Line Lobby ID: "+str(ARGUMENTS[1]))
				_join_Lobby(int(ARGUMENTS[1]))

func _on_Open_Lobby_List_pressed() -> void:
	# Set distance to worldwide
	Steam.addRequestLobbyListDistanceFilter(Steam.LobbyDistanceFilter.LOBBY_DISTANCE_FILTER_WORLDWIDE)

	print("Requesting a lobby list")
	Steam.requestLobbyList()

func _on_Lobby_Match_List(lobbies: Array) -> void:
	var lobbies_info = []
	for lobby in lobbies:
		var lobby_info = {}

		# Pull lobby data from Steam, these are specific to our example
		lobby_info["id"] = lobby
		lobby_info["name"] = Steam.getLobbyData(lobby, "name")
		lobby_info["mode"] = Steam.getLobbyData(lobby, "mode")
		lobby_info["num_members"] = Steam.getNumLobbyMembers(lobby)
		lobby_info["num_members"] = Steam.getNumLobbyMembers(lobby)

		lobbies_info.push_back(lobby_info)

	lobby_list_update.emit(lobbies_info)

func _join_Lobby(lobby_id: int) -> void:
	print("Attempting to join lobby "+str(lobby_id)+"...")

	# Clear any previous lobby members lists, if you were in a previous lobby
	LOBBY_MEMBERS.clear()

	# Make the lobby join request to Steam
	Steam.joinLobby(lobby_id)

func _on_Lobby_Joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	# If joining was successful
	if response == 1:
		# Set this lobby ID as your lobby ID
		LOBBY_ID = lobby_id

		# Get the lobby members
		_get_Lobby_Members()

		# Make the initial handshake
		_make_P2P_Handshake()

		lobby_joined.emit()

	# Else it failed for some reason
	else:
		# Get the failure reason
		var FAIL_REASON: String

		match response:
			2:  FAIL_REASON = "This lobby no longer exists."
			3:  FAIL_REASON = "You don't have permission to join this lobby."
			4:  FAIL_REASON = "The lobby is now full."
			5:  FAIL_REASON = "Uh... something unexpected happened!"
			6:  FAIL_REASON = "You are banned from this lobby."
			7:  FAIL_REASON = "You cannot join due to having a limited account."
			8:  FAIL_REASON = "This lobby is locked or disabled."
			9:  FAIL_REASON = "This lobby is community locked."
			10: FAIL_REASON = "A user in the lobby has blocked you from joining."
			11: FAIL_REASON = "A user you have blocked is in the lobby."

		print(FAIL_REASON)

		#Reopen the lobby list
		_on_Open_Lobby_List_pressed()

func _get_Lobby_Members() -> void:
	# Clear your previous lobby list
	LOBBY_MEMBERS.clear()

	# Get the number of members from this lobby from Steam
	var MEMBERS: int = Steam.getNumLobbyMembers(LOBBY_ID)

	# Get the data of these players from Steam
	for MEMBER in range(0, MEMBERS):
		# Get the member's Steam ID
		var MEMBER_STEAM_ID: int = Steam.getLobbyMemberByIndex(LOBBY_ID, MEMBER)

		# Get the member's Steam name
		var MEMBER_STEAM_NAME: String = Steam.getFriendPersonaName(MEMBER_STEAM_ID)

		# Add them to the list
		LOBBY_MEMBERS.append({"steam_id":MEMBER_STEAM_ID, "steam_name":MEMBER_STEAM_NAME})

	lobby_update.emit()

# A user's information has changed
func _on_Persona_Change(_steam_id: int, _flag: int) -> void:
	# Make sure you're in a lobby and this user is valid or Steam might spam your console log
	if LOBBY_ID > 0:
		#print("[STEAM] A user ("+str(steam_id)+") had information change, update the lobby list")

		# Update the player list
		_get_Lobby_Members()

func _make_P2P_Handshake() -> void:
	print("Sending P2P handshake to the lobby")

	_send_P2P_Packet(0, {"message":"handshake", "from":STEAM_ID})

func _send_P2P_Packet(target: int, packet_data: Dictionary) -> void:
	# Set the send_type and channel
	var SEND_TYPE: int = Steam.P2P_SEND_RELIABLE
	var CHANNEL: int = 0

	# Create a data array to send the data through
	var DATA: PackedByteArray = []
	DATA.append_array(var_to_bytes(packet_data))

	# If sending a packet to everyone
	if target == 0:
		# If there is more than one user, send packets
		if LOBBY_MEMBERS.size() > 1:
			# Loop through all members that aren't you
			for MEMBER in LOBBY_MEMBERS:
				if MEMBER['steam_id'] != STEAM_ID:
					Steam.sendP2PPacket(MEMBER['steam_id'], DATA, SEND_TYPE, CHANNEL)
	# Else send it to someone specific
	else:
		Steam.sendP2PPacket(target, DATA, SEND_TYPE, CHANNEL)

func _on_Lobby_Chat_Update(_lobby_id: int, change_id: int, _making_change_id: int, chat_state: int) -> void:
	# Get the user who has made the lobby change
	var CHANGER: String = Steam.getFriendPersonaName(change_id)

	# If a player has joined the lobby
	if chat_state == 1:
		print(str(CHANGER)+" has joined the lobby.")

	# Else if a player has left the lobby
	elif chat_state == 2:
		print(str(CHANGER)+" has left the lobby.")

	# Else if a player has been kicked
	elif chat_state == 8:
		print(str(CHANGER)+" has been kicked from the lobby.")

	# Else if a player has been banned
	elif chat_state == 16:
		print(str(CHANGER)+" has been banned from the lobby.")

	# Else there was some unknown change
	else:
		print(str(CHANGER)+" did... something.")

	# Update the lobby now that a change has occurred
	_get_Lobby_Members()

func _on_Send_Chat_pressed() -> void:
	# Get the entered chat message
	var MESSAGE: String = $Chat.get_text()

	# If there is even a message
	if MESSAGE.length() > 0:
		# Pass the message to Steam
		var SENT: bool = Steam.sendLobbyChatMsg(LOBBY_ID, MESSAGE)

		# Was it sent successfully?
		if not SENT:
			print("ERROR: Chat message failed to send.")

	# Clear the chat input
	$Chat.clear()

func _leave_Lobby() -> void:
	# If in a lobby, leave it
	if LOBBY_ID != 0:
		# Send leave request to Steam
		Steam.leaveLobby(LOBBY_ID)

		# Wipe the Steam lobby ID then display the default lobby ID and player list title
		LOBBY_ID = 0

		# Close session with all users
		for MEMBERS in LOBBY_MEMBERS:
			# Make sure this isn't your Steam ID
			if MEMBERS['steam_id'] != STEAM_ID:
				# Close the P2P session
				Steam.closeP2PSessionWithUser(MEMBERS['steam_id'])

		# Clear the local lobby list
		LOBBY_MEMBERS.clear()

func _on_Lobby_Join_Requested(lobby_id: int, friendID: int) -> void:
	# Get the lobby owner's name
	var OWNER_NAME: String = Steam.getFriendPersonaName(friendID)

	print("Joining "+str(OWNER_NAME)+"'s lobby...")

	# Attempt to join the lobby
	_join_Lobby(lobby_id)

func is_host():
	if LOBBY_ID != 0:
		return Steam.getLobbyOwner(LOBBY_ID) == STEAM_ID
	return true
