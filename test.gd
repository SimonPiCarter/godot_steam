extends Node2D

#####################
## UI
######################

@onready var join = $VBoxContainer/join
@onready var list = $VBoxContainer/list
@onready var send = $VBoxContainer/send

func _ready():
	join.pressed.connect(GlobalSteam._create_Lobby)
	list.pressed.connect(GlobalSteam._on_Open_Lobby_List_pressed)
	send.pressed.connect(send_data)

	GlobalSteam.handle_data.connect(handle_data)
	GlobalSteam.lobby_list_update.connect(refresh_list)

func send_data():
	var data = {"message":"handshake", "from":GlobalSteam.STEAM_ID, "data": []}
	data["data"].push_back(12)
	data["data"].push_back("test")
	data["data"].push_back(true)

	GlobalSteam._send_P2P_Packet(0, data)

func handle_data(data):
	# Print the packet to output
	print("Packet: "+str(data))

func refresh_list(lobbies):
	for child in $VBoxContainer/ScrollContainer/VBoxContainer.get_children():
		child.queue_free()

	for lobby in lobbies:
		# Create a button for the lobby
		var button: Button = Button.new()
		button.set_text("Lobby "+str(lobby["id"])+": "+str(lobby["name"])+" ["+str(lobby["mode"])+"] - "+str(lobby["num_members"])+" Player(s)")
		button.set_size(Vector2(800, 50))
		button.set_name("lobby_"+str(lobby["id"]))
		button.connect("pressed", GlobalSteam._join_Lobby.bind(lobby["id"]))

		# Add the new lobby to the list
		$VBoxContainer/ScrollContainer/VBoxContainer.add_child(button)
