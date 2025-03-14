var flippedCards = [];
var cardStates = {};
var flippedCardsAmount = 0;
var solvedCards = [];
var knownCards = {};
var moves = 0;


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

    var socket = new WebSocket(`ws://${server_ip}/gameroom/memory/game`);

    socket.onopen = function() {
        console.log("WebSocket is open now.");
        socket.send("Here's some text that the server is urgently awaiting!");
        console.log("Sent message: Here's some text that the server is urgently awaiting!");
    };

    socket.onmessage = function(event) {
        console.log("WebSocket message received:", event.data);
    };

    socket.onclose = function(_event) {
        console.log("WebSocket is closed now.");
    };

    socket.onerror = function(error) {
        console.log("WebSocket error:", error);
    };
};



function flipCard(card_id) {
    var card = document.getElementById("memory_field" + card_id);
    
    if (cardStates[card_id] !== "flipped" && solvedCards.includes(card_id) === false && flippedCards.includes(card_id) === false) {
        cardStates[card_id] = "flipped";
        flippedCardsAmount++;
        flippedCards.push(card_id);
        console.log("flipped card " + card_id);

        sendMoves(card_id).then(() => {
            console.log("sent and received image for card " + card_id);
            setImage(card_id);
            if (flippedCardsAmount === 2) {
                moves++;
                console.log("moves: " + moves);
                checkForSolvedCards();
                console.log("checked for solved cards");
            }
        });

    } else {
        console.log("already flipped card " + card_id);
        return;
    }
    if (flippedCardsAmount > 2) {
        console.log("flipped cards amount = " + flippedCardsAmount + ", resetting flipped cards");
        resetFlippedCards(card_id);
        console.log("reset flipped cards to " + flippedCardsAmount);
    }
}

function checkForSolvedCards() {
    var firstCard = flippedCards[0];
    var secondCard = flippedCards[1];
    if (knownCards[firstCard] === knownCards[secondCard]) {
        solvedCards.push(firstCard, secondCard);
        console.log("cards " + firstCard + " and " + secondCard + " are solved");
        if (solvedCards.length === 16) {
            console.log("all cards are solved");
            var url = "/gameroom/memory/win/" + moves;
            window.location.href = url;
        }
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
            var game_id = document.cookie.split('; ').find(row => row.startsWith('memory=')).split('=')[1];
            socket.send(JSON.stringify({ type: "flip_card", card_id: card_id, game: "memory", game_id: game_id }));
            console.log("Sent moves: " + card_id);

            socket.onmessage = function(event) {
                console.log("WebSocket message received:", event.data);
                if (!knownCards[card_id]) {
                    knownCards[card_id] = event.data;
                }
                resolve(event.data);
            };
        } else {
            console.log("WebSocket is not open. Ready state: " + socket.readyState);
            reject("WebSocket is not open");
        }
    });
}