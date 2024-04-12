module dacade_deepbook::auction {
    // Import necessary modules and types
    use sui::sui::SUI;
    use sui::tx_context::{TxContext, sender};
    use sui::coin::{Coin, Self};
    use sui::balance::{Self, Balance};
    use sui::transfer::Self;
    use sui::clock::{Clock, timestamp_ms};
    use sui::object::{Self, UID, ID};
    use sui::table::{Self, Table};

    // Define error constants
    const ERROR_INVALID_CAP: u64 = 0;
    const ERROR_INSUFFICIENT_FUNDS: u64 = 1;
    const ERROR_ALREADY_BID: u64 = 2;
    const ERROR_NOT_BID: u64 = 3;
    const ERROR_AUCTION_COMPLETED: u64 = 4;

    // Define structs for auctions, auction caps, and winning bidders
    struct Auction has key, store {
        id: UID,
        car_id: u64,
        deposit: Balance<SUI>,
        bidders: Table<address, bool>,
        starting_price: u64,
        start_time: u64,
        end_time: u64,
        active: bool,
    }

    struct AuctionCap has key {
        id: UID,
        auction_id: ID,
    }

    struct WinningBidder has key {
        id: UID,
        auction_id: ID,
        winner: address,
        winning_bid: u64,
    }

    // Define constants
    const MIN_BID_INCREMENT: u64 = 10; // Adjust this value as needed
    const MAX_AUTO_BID_AMOUNT: u64 = 1000; // Adjust this value as needed

    // Function to create a new auction
    public fun new_auction(car_id: u64, starting_price: u64, duration: u64, c: &Clock, ctx: &mut TxContext) {
        // Generate unique ID for the auction
        let id_ = object::new(ctx);
        let inner = object::uid_to_inner(&id_);
        // Create the auction object
        let auction = Auction {
            id: id_,
            car_id: car_id,
            deposit: balance::zero(),
            bidders: table::new(ctx),
            starting_price: starting_price,
            start_time: timestamp_ms(c),
            end_time: timestamp_ms(c) + duration,
            active: true,
        };
        // Share the auction object
        transfer::share_object(auction);
        // Create a new auction cap
        let cap = AuctionCap {
            id: object::new(ctx),
            auction_id: inner,
        };
        // Transfer the auction cap to the sender
        transfer::transfer(cap, sender(ctx));
    }

    // Function to place a bid on an auction
    public fun place_bid(cap: &AuctionCap, self: &mut Auction, c: &Clock, amount: u64, ctx: &mut TxContext) : Coin<SUI> {
        // Validate the auction cap
        assert!(cap.auction_id == object::id(self), ERROR_INVALID_CAP);
        // Check if the bid amount is greater than the starting price
        assert!(amount > self.starting_price, ERROR_INSUFFICIENT_FUNDS);
        // Check if the auction is still active
        assert!(timestamp_ms(c) < self.end_time, ERROR_AUCTION_COMPLETED);
        // Check if the sender has already placed a bid
        assert!(!table::contains(&self.bidders, sender(ctx)), ERROR_ALREADY_BID);

        // Check if the bidder has sufficient funds
        assert!(balance::value(&self.deposit) >= amount, ERROR_INSUFFICIENT_FUNDS);

        // Take the bid amount from the bidder's deposit
        let coin_ = coin::take(&mut self.deposit, amount, ctx);

        // Add the bidder to the list of bidders
        table::add(&mut self.bidders, sender(ctx), true);

        coin_
    }

    // Function to place a bid on an auction with minimum bid increment
    public fun place_bid_with_increment(cap: &AuctionCap, self: &mut Auction, c: &Clock, amount: u64, ctx: &mut TxContext) : Coin<SUI> {
        // Validate the auction cap
        assert!(cap.auction_id == object::id(self), ERROR_INVALID_CAP);
        // Check if the bid amount is greater than or equal to the starting price plus the minimum bid increment
        assert!(amount >= self.starting_price + MIN_BID_INCREMENT, ERROR_INSUFFICIENT_FUNDS);
        // Check if the auction is still active
        assert!(timestamp_ms(c) < self.end_time, ERROR_AUCTION_COMPLETED);
        // Check if the sender has already placed a bid
        assert!(!table::contains(&self.bidders, sender(ctx)), ERROR_ALREADY_BID);

        // Check if the bidder has sufficient funds
        assert!(balance::value(&self.deposit) >= amount, ERROR_INSUFFICIENT_FUNDS);

        // Take the bid amount from the bidder's deposit
        let coin_ = coin::take(&mut self.deposit, amount, ctx);

        // Add the bidder to the list of bidders
        table::add(&mut self.bidders, sender(ctx), true);

        coin_
    }

    // Function to place a bid on an auction
    public fun bid(self: &mut Auction, coin: Coin<SUI>, c: &Clock, ctx: &mut TxContext) : WinningBidder {
        // Check if the auction is still active
        assert!(timestamp_ms(c) < self.end_time, ERROR_AUCTION_COMPLETED);
        // Copy the value of the coin before moving it
        let coin_value = coin::value(&coin);
        // Check if the bid amount is greater than the starting price
        assert!(coin_value > self.starting_price, ERROR_INSUFFICIENT_FUNDS);
        // Check if the sender has already placed a bid
        assert!(!table::contains(&self.bidders, sender(ctx)), ERROR_ALREADY_BID);

        // Move the bid amount into the auction's deposit
        let balance_ = coin::into_balance(coin);
        balance::join(&mut self.deposit, balance_);

        // Add the bidder to the list of bidders
        table::add(&mut self.bidders, sender(ctx), true);

        // Create a winning bidder object
        let winning_bidder = WinningBidder {
            id: object::new(ctx),
            auction_id: object::id(self),
            winner: sender(ctx),
            winning_bid: coin_value,
        };
        winning_bidder
    }

    // Function to end an auction
    public fun end_auction(self: &mut Auction, c: &Clock) {
        // Check if the auction has ended
        assert!(timestamp_ms(c) >= self.end_time, ERROR_AUCTION_COMPLETED);
        // Set the auction as inactive
        self.active = false;
    }

    // Function to get the winning bidder of an auction
    public fun get_winning_bidder(winner: &WinningBidder) : (ID, address) {
        (winner.auction_id, winner.winner)
    }

    // Function to check if an auction has ended
    public fun get_ended_auctions(self: &Auction) : bool {
        !self.active
    }

    // Function to retrieve the result of an auction
    public fun get_auction_result(self: &Auction) : WinningBidder {
        assert!(!self.active, ERROR_AUCTION_COMPLETED);
        // Use the determine_winner function to get the winner
        determine_winner(self)
    }

    // Function to check if an auction has ended
    public fun get_ended_auctions(self: &Auction) : bool {
        !self.active
    }


    // Function to check if a user is an active bidder in an auction
    public fun get_active_bidders(self: &Auction, user: address) : bool {
        // Check if the user is a bidder in the auction
        assert!(table::contains(&self.bidders, user), ERROR_NOT_BID);
        true
    }

    // Function to withdraw a bid from an auction
    public fun withdraw_bid(cap: &AuctionCap, self: &mut Auction, ctx: &mut TxContext) : Coin<SUI> {
        // Validate the auction cap
        assert!(cap.auction_id == object::id(self), ERROR_INVALID_CAP);
        // Check if the sender has placed a bid
        assert!(table::contains(&self.bidders, sender(ctx)), ERROR_NOT_BID);
        
        // Retrieve the bid amount from the auction's deposit and remove the bidder from the list
        let bid_amount = balance::value(&self.deposit);
        let coin_ = coin::take(&mut self.deposit, bid_amount, ctx);
        table::remove(&mut self.bidders, sender(ctx));
        
        coin_
    }

    // Function to check if a bid meets the minimum bid increment requirement
    public fun meets_min_bid_increment(current_bid: u64, new_bid: u64) : bool {
        new_bid >= current_bid + MIN_BID_INCREMENT
    }

    // Define a constant for the maximum auto-bid amount
    const MAX_AUTO_BID_AMOUNT: u64 = 1000; // Adjust this value as needed

    // Function to place an auto-bid on an auction
    public fun place_auto_bid(cap: &AuctionCap, self: &mut Auction, c: &Clock, ctx: &mut TxContext) : Coin<SUI> {
        // Calculate the auto-bid amount (e.g., based on user preferences)
        let auto_bid_amount = MAX_AUTO_BID_AMOUNT; // Example: Fixed auto-bid amount
        
        // Call the place_bid function with the auto-bid amount
        place_bid_with_increment(cap, self, c, auto_bid_amount, ctx)
    }

    // Function to retrieve bidding history of an auction
    public fun get_bidding_history(self: &Auction) : Table<address, u64> {
        self.bidders
    }
}


