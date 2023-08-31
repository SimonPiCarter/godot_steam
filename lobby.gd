extends Control

@onready var create = $margin/lobby_selector/VBoxContainer/create
@onready var refresh = $margin/lobby_selector/VBoxContainer/refresh
@onready var list = $margin/lobby_selector/lobby_list/scroller/list
@onready var player_list = $margin/room/player_list

@onready var room = $margin/room
@onready var lobby_selector = $margin/lobby_selector

@onready var level = $margin/room/VBoxContainer/level
@onready var start = $margin/room/VBoxContainer/start
@onready var leave = $margin/room/VBoxContainer/leave

signal launch_game()

# map of player node added to the player list
# used to update team and remove
var player_node = {}

# Called when the node enters the scene tree for the first time.
func _ready():
	room.hide()
	lobby_selector.show()

	create.pressed.connect(GlobalSteam._create_Lobby)
	refresh.pressed.connect(GlobalSteam._on_Open_Lobby_List_pressed)

	GlobalSteam.handle_data.connect(handle_data)
	GlobalSteam.lobby_list_update.connect(refresh_list)
	GlobalSteam.lobby_joined.connect(join_lobby)
	GlobalSteam.lobby_update.connect(update_lobby)

	leave.pressed.connect(leave_lobby)
	level.item_selected.connect(on_level_change)

	GlobalSteam._on_Open_Lobby_List_pressed()

######################
##     UI handling
######################

func refresh_list(lobbies):
	for child in list.get_children():
		child.queue_free()

	for lobby in lobbies:
		# Create a button for the lobby
		var button: Button = Button.new()
		button.set_text("Lobby "+str(lobby["id"])+": "+str(lobby["name"])+" ["+str(lobby["mode"])+"] - "+str(lobby["num_members"])+" Player(s)")
		button.set_size(Vector2(800, 50))
		button.set_name("lobby_"+str(lobby["id"]))
		button.connect("pressed", GlobalSteam._join_Lobby.bind(lobby["id"]))

		# Add the new lobby to the list
		list.add_child(button)

func join_lobby():
	lobby_selector.hide()
	room.show()

	for node in player_node.values():
		if node != null:
			node.queue_free()
	player_node.clear()
	# update player node
	update_lobby()

	start.disabled = not GlobalSteam.is_host()
	level.disabled = not GlobalSteam.is_host()

func update_lobby():

	var members_id = []

	# add new players
	for member in GlobalSteam.LOBBY_MEMBERS:
		if not player_node.has(member["steam_id"]) or player_node[member["steam_id"]] == null:
			#create new node
			var node = preload("res://player_lobby.tscn").instantiate()
			player_node[member["steam_id"]] = node
			player_list.add_child(node)
			node.player_name.text = member["steam_name"]
			node.kick.disabled = not GlobalSteam.is_host() or member["steam_id"] == GlobalSteam.get_host()
			node.player.disabled = not GlobalSteam.is_host() and member["steam_id"] != GlobalSteam.STEAM_ID
			node.player_id = member["steam_id"]
		members_id.push_back(member["steam_id"])

	# remove old players
	for node in player_node.values():
		if node != null and not node.player_id in members_id:
			node.queue_free()

func leave_lobby():
	lobby_selector.show()
	room.hide()
	GlobalSteam.leave_lobby()

######################
##     Data sync
######################

enum SyncType { LevelChange, TeamChange, StartGame }

#
# Data sync package nomenclature
# - data["sync_type"] in SyncType enum
# - LevelChange
#   - data["level"] in 0,1
# - TeamChange
#   - data["id"] : int
#   - data["team_id"] : int
# - StartGame
#   - launch the game
#

func handle_data(data):
	# Print the packet to output
	print("Packet: "+str(data))

	if data.has("sync_type"):
		if data["sync_type"] == SyncType.LevelChange:
			level.selected = data["level"]
		elif data["sync_type"] == SyncType.TeamChange:
			player_node[data["id"]].player.selected = data["team_id"]
		elif data["sync_type"] == SyncType.StartGame:
			launch_game.emit()

func on_level_change(value):
	var data = {}
	data["sync_type"] = SyncType.LevelChange
	data["level"] = value

	GlobalSteam._send_P2P_Packet(0, data)

func on_team_change(node):
	var data = {}
	data["sync_type"] = SyncType.TeamChange
	data["id"] = node.player_id
	data["team_id"] = node.player_id

	GlobalSteam._send_P2P_Packet(0, data)
