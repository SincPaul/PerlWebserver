
var socket;
var timeout;
var timeoutInSec = 15;
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

    socket = new WebSocket(`ws://${server_ip}/gameroom/memory/multi`);
    
    socket.onopen = function(event) {
        console.log("WebSocket is open now.");
        game_id_value = document.cookie.split('; ').find(row => row.startsWith('memory=')).split('=')[1];
        msg = JSON.stringify({ game_id: game_id_value, type: "multi_start_game", game: "memory", wstype: "game" });
        socket.send(msg);
        console.log("Sent message: " + msg);
    
        timeout = setTimeout(function() {
            console.log("No message received in " + timeoutInSec + " seconds. Sending message and disconnecting.");
            msg = JSON.stringify({ game_id: game_id_value, type: "opponent_not_connected", game: "memory", wstype: "game" });
            socket.send(msg);
            socket.close();
            socket.onclose = function(event) {
                alert("Opponent not connected. Redirecting to main page.");
                window.location.href = "/gameroom/memory";
            };
        }, 15000);
    
        const player1Name = document.getElementsByClassName("player1_name")[0].innerHTML;
    
        const player2Name = document.getElementsByClassName("player2_name")[0].innerHTML;
    
        player1 = player1Name ? player1Name : "Unknown Player 1";
        player2 = player2Name ? player2Name : "Unknown Player 2";
    
        player1 = decodeURIComponent(player1);
        player2 = decodeURIComponent(player2);
    
        myUsername = document.getElementsByClassName("my_username")[0].innerHTML;
        // myUsername = document.cookie.split('; ').find(row => row.startsWith('username=')).split('=')[1];
        console.log("Username from cookie: " + myUsername);
        console.log(player1);
        console.log(player2);
        currentPlayer = decodeURIComponent(player1);
    };

    setupSocketHandlers();
};



// socket.onmessage = function(event) {
//     console.log("WebSocket message received:", event.data);

//     var data = JSON.parse(event.data);

//     console.log(data.type);
    
//     if (data.type === "flipped_card") {
//         var card_id = data.card_flipped;
//         var card_name = data.card_name;
//         var imageData = card_name.replace(/"/g, '');

//         console.log("Received card: " + card_id + " with image: " + imageData + "\nCard Name: " + card_name);


//         var card = document.getElementById("memory_field" + card_id);
//         card.getElementsByTagName("img")[0].src = imageData;
//         knownCards[card_id] = imageData;
//         setImage(card_id);
//         moveUtils(card_id);
//     }

// };


// socket.onclose = function(event) {
//     console.log("WebSocket is closed now.");
// };

