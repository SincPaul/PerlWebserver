var flippedCards = [];
var cardStates = {};
var flippedCardsAmount = 0;
var solvedCards = [];
var knownCards = {};
var moves = 0;
var finish;
var player1 = "placeholder";
var player2 = "placeholder";
var myUsername = "placeholder";
var currentPlayer = player1;
var timeout;
var game_id = document.cookie.split('; ').find(row => row.startsWith('memory=')).split('=')[1];



function flipCard(card_id) {
    console.log("CURRENT PLAYER: " + decodeURI(currentPlayer));
    console.log("MY USERNAME: " + decodeURI(myUsername));
    if (decodeURI(currentPlayer) !== decodeURI(myUsername)) {
        console.log("NOT YOUR TURN");
        return;
    }

    if (cardStates[card_id] !== "flipped" && solvedCards.includes(card_id) === false && flippedCards.includes(card_id) === false) {
        sendMoves(card_id);
    } else {
        console.log("already flipped card " + card_id);
        return;
    }
    
}

function checkForSolvedCards() {
    var firstCard = flippedCards[0];
    var secondCard = flippedCards[1];
    if (knownCards[firstCard] === knownCards[secondCard]) {
        solvedCards.push(firstCard, secondCard);
        console.log("cards " + firstCard + " and " + secondCard + " are solved");
        console.log("solved cards: " + solvedCards.length);
        socket.send(JSON.stringify({ type: "solved_cards", solved_cards: firstCard + "," + secondCard, player: encodeURI(currentPlayer), game_id: game_id, game: "memory", wstype: "game" }));
        updateSolvedCardsGui();
        // if (solvedCards.length === 16) {
        //     finish = true;
        //     console.log("all cards are solved");
        //     var url = "/gameroom/memory/end/" + game_id;
        //     window.location.href = url;
        // }
        return true;
    }
}

function updateSolvedCardsGui() {
    if (currentPlayer === player1) {
        currentPlayerScore = "player1_score";
    } else {
        currentPlayerScore = "player2_score";
    }
    var scoreElement = document.getElementsByClassName(currentPlayerScore)[0];
    if (scoreElement) {
        var player_score = parseInt(scoreElement.innerHTML);
        player_score++;
        scoreElement.innerHTML = player_score;
    }
}

function resetFlippedCards(card_id) {
    flippedCards.splice(0, flippedCards.length-1).forEach(function(card_id) {
        if (solvedCards.includes(card_id)) {
            return;
        }
        var card = document.getElementById("memory_field" + card_id);
        cardStates[card_id] = "back";
        card.getElementsByTagName("img")[0].src = "src/deckblatt.png";
    });

    flippedCardsAmount = 1;
    flippedCards = [card_id];
    return;
}

function moveUtils(card_id) {
    cardStates[card_id] = "flipped";
    flippedCardsAmount++;
    flippedCards.push(card_id);
    console.log("flipped card " + card_id);
    
    if (flippedCardsAmount === 2) {
        moves++;
        console.log("moves: " + moves);
        if (!checkForSolvedCards()) {
            console.log("checked for solved cards");
    
            currentPlayer = currentPlayer === player1 ? player2 : player1;
            console.log("Player turn: " + currentPlayer);
        } 
    }

    if (flippedCardsAmount > 2) {
        console.log("flipped cards amount = " + flippedCardsAmount + ", resetting flipped cards");
        resetFlippedCards(card_id);
        console.log("reset flipped cards to " + flippedCardsAmount);
    }
}


// function sendAndReceiveImg(card_id) {
//     var url = "/gameroom/memory/src/card/" + card_id;

//     return fetch(url)
//     .then(response => response.text())
//     .then(data => {
//         var card = document.getElementById("memory_field" + card_id).getElementsByTagName("img")[0];
//         card.src = data;
//         knownCards[card_id] = data;
        
//     })
//     .catch(error => console.error('Error:', error));
// }

function setImage(card_id) {
    var card = document.getElementById("memory_field" + card_id);
    if (knownCards[card_id]) {
        card.getElementsByTagName("img")[0].src = knownCards[card_id];
    }
}

function sendMoves(card_id) {
    return new Promise((resolve, reject) => {
        if (socket.readyState === WebSocket.OPEN) {
            socket.send(JSON.stringify({ type: "flip_card", card_id: card_id, game: "memory", game_id: game_id, wstype: "game" }));
            console.log("Sent moves: " + card_id);
            
            resolve();
            
        } else {
            console.log("WebSocket is not open. Ready state: " + socket.readyState);
            reject("WebSocket is not open");
        }
    });
}

function setupSocketHandlers() {

    socket.onmessage = function(event) {
        console.log("WebSocket message received:", event.data);
        clearTimeout(timeout);

        if (event.data === "pong") {
            console.log("Received pong.");
            var currentTime = Date.now();
            var ping = currentTime - lastPingTime;
            console.log("Ping: " + ping + "ms");
            document.getElementById('ping').textContent = ping;
            return;
        }

        var data = JSON.parse(event.data);

        if (!data) {
            return;
        }

        console.log(data.type);

        
        if (data.type === "flipped_card") {
            var card_id = data.card_flipped;
            var card_name = data.card_name;
            var imageData = card_name.replace(/"/g, '');

            console.log("Received card: " + card_id + " with image: " + imageData + "\nCard Name: " + card_name);


            var card = document.getElementById("memory_field" + card_id);
            card.getElementsByTagName("img")[0].src = imageData;
            knownCards[card_id] = imageData;
            setImage(card_id);
            moveUtils(card_id);
        }

        if (data.type === "both_connected") {
            console.log("Both players are connected.");
            connectionLayer = document.getElementById("wait_connection_layer");
            connectionLayer.style.display = "none";
            pingInterval = setInterval(() => {
                lastPingTime = Date.now();
                socket.send("ping");
            }, 1000);
        }

        if (data.type === "opponent_disconnected") {
            var disconnectedPlayer = data.player;
            disconnectedPlayer = decodeURI(disconnectedPlayer);
            alert(disconnectedPlayer + " disconnected. Redirecting to main page.");
            window.location.href = "/gameroom/memory";
        }

        if (data.type === "game_end") {
            finish = true;
            console.log("all cards are solved");
            var url = "/gameroom/memory/end/" + game_id;
            window.location.href = url;
        }
    };

    socket.onclose = function(event) {
        if (!finish) {
            alert("Lost connection to server. Redirecting to main page.");
            window.location.href = "/gameroom/memory";
        }
    };
}