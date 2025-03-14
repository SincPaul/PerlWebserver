var game_id_value = "game_id_placeholder";
var socket;

(async function() {
    await connectToWebsocket();
})();



async function connectToWebsocket() {
    var server_ip = await fetch("/server/ip")
        .then(response => response.text())
        .then(data => {
            return data;
        })
        .catch(error => console.error('Error:', error));

    socket = new WebSocket(`ws://${server_ip}/gameroom/memory/queue`);
    
    socket.onopen = function(event) {
        console.log("WebSocket is open now.");
        socket.send(JSON.stringify({ type: "join_queue", game: "memory", game_id: game_id_value, wstype: "game" }));
    };
    
    socket.onmessage = function(event) {
        console.log("WebSocket message received:", event.data);
        var data = JSON.parse(event.data);
    
        if (data.type === "start_game") {
            game_id_value = data.game_id;
            console.log("Game ID: " + game_id_value);
            Document.cookie = "memory=" + game_id_value + "; SameSite=Strict";
            window.location.href = "/gameroom/memory/2player";
        }
        if (data.type === "created queue: ") {
            game_id_value = data.split(":")[1].trim();
            console.log("Game ID: " + game_id_value);
            Document.cookie = "p1=p1; SameSite=Strict";
        }
    };
};
