(async function() {
    await connectToWebsocket();
})();


var socket;

async function connectToWebsocket() {
    var server_ip = await fetch("/server/ip")
        .then(response => response.text())
        .then(data => {
            return data;
        })
        .catch(error => console.error('Error:', error));

    socket = new WebSocket(`ws://${server_ip}/gameroom/memory/alone`);
    
    socket.onopen = function(event) {
        console.log("WebSocket is open now.");
        socket.send(JSON.stringify({ type: "alone_start", game: "memory", game_id: game_id, wstype: "game" }));
        console.log("Sent message: Here's some text that the server is urgently awaiting!");
    };
    
    socket.onerror = function(error) {
        console.log("WebSocket error:", error);
    };

    setupSocketHandlers();
};




// socket.onmessage = function(event) {
//     console.log("WebSocket message received:", event.data);

//     socket.onmessage = function(event) {
//         console.log("WebSocket message received:", event.data);

//         var imageData = event.data.replace(/"/g, '');
//         if (!knownCards[card_id]) {
//             knownCards[card_id] = imageData;
//         }
//         resolve(event.data);
//     };
// };

