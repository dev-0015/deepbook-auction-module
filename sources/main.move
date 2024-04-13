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
    struct Auction<T: key + store> has key, store {
        id: UID,
        owner: address,
        car_id: u64,
        bidders: Table<address, bool>,
        starting_price: u64,
        highest_bid: u64,
        highest_address: address,
        start_time: u64,
        end_time: u64,
        item: T,
        deposit: bool,
        active: bool,
    }

    struct AuctionCap has key {
        id: UID,
        auction_id: ID,
    }

    struct Bid has key {
        id: UID,
        auction_id: ID,
        balance: Balance<SUI>,
        winner: address,
        winning_bid: u64,
    }

    // Function to create a new auction
    public fun new_auction<T: key + store>(car_id: u64, starting_price: u64, duration: u64, c: &Clock, item_: T, ctx: &mut TxContext) {
        // Generate unique ID for the auction
        let id_ = object::new(ctx);
        let inner = object::uid_to_inner(&id_);
        // Create the auction object
        let auction = Auction {
            id: id_,
            owner: sender(ctx),
            car_id: car_id,
            bidders: table::new(ctx),
            starting_price: starting_price,
            highest_bid: 0,
            highest_address: sender(ctx),
            start_time: timestamp_ms(c),
            end_time: timestamp_ms(c) + duration,
            item: item_,
            deposit: false,
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
    public fun bid<T: key + store>(self: &mut Auction<T>, coin: Coin<SUI>, c: &Clock, ctx: &mut TxContext) : Bid {
        // Check if the auction is still active
        assert!(timestamp_ms(c) < self.end_time, ERROR_AUCTION_COMPLETED);
        // Check if the bid amount is greater than the starting price
        assert!(coin::value(&coin) > self.starting_price, ERROR_INSUFFICIENT_FUNDS);
        // Check if the sender has already placed a bid
        assert!(!table::contains(&self.bidders, sender(ctx)), ERROR_ALREADY_BID);
        // Add the bidder to the list of bidders
        table::add(&mut self.bidders, sender(ctx), true);
        // convert to balance 
        let balance_ = coin::into_balance(coin);
        // convert to u64
        let amount = balance::value(&balance_);
        if(amount > self.highest_bid) {
            self.highest_address = sender(ctx);
            self.highest_bid = amount;
        };
        // Create a winning bidder object
        let winning_bidder = Bid {
            id: object::new(ctx),
            auction_id: object::id(self),
            balance: balance::zero(),
            winner: sender(ctx),
            winning_bid: amount,
        };
        // join the balance 
        balance::join(&mut winning_bidder.balance, balance_);
        winning_bidder
    }

    //Function to place a bid on an auction with minimum bid increment
    public fun place_bid_with_increment<T: key + store>(self: &mut Bid, auction: &mut Auction<T>, c: &Clock, coin_: Coin<SUI>, ctx: &mut TxContext) {
        // Check if the auction is still active
        assert!(timestamp_ms(c) < auction.end_time, ERROR_AUCTION_COMPLETED);        
        // Check if the bid amount is greater than or equal to the starting price plus the minimum bid increment
        let current = balance::value(&self.balance);
        assert!(coin::value(&coin_) + current > auction.highest_bid, ERROR_INSUFFICIENT_FUNDS);
        // Take the bid amount from the bidder's deposit
        let balance = coin::into_balance(coin_);
        let amount = balance::value(&balance);
        // join the balance in Bid Object 
        balance::join(&mut self.balance, balance);
        self.winning_bid = self. winning_bid + amount;
        // set te auction parameters
        auction. highest_bid = self.winning_bid;
        auction.highest_address = sender(ctx);
    }

    public fun transfer_item_price<T: key + store>(self: Bid, auction: &mut Auction<T>, ctx: &mut TxContext) {
        assert!(sender(ctx) == auction.highest_address, ERROR_NOT_BID);
        assert!(!auction.active, ERROR_NOT_BID);
        let Bid {
            id: id_,
            auction_id: _,
            balance: balance_,
            winner: _,
            winning_bid: _
        } = self; 
        object::delete(id_);
        let coin_ = coin::from_balance(balance_, ctx);
        transfer::public_transfer(coin_, auction.owner);
        auction.deposit = true;
    }

    // Function to end an auction
    public fun end_auction<T: key + store>(_:&AuctionCap, self: &mut Auction<T>, c: &Clock) {
        // Check if the auction has ended
        assert!(timestamp_ms(c) >= self.end_time, ERROR_AUCTION_COMPLETED);
        // Set the auction as inactive
        self.active = false;
    }

    // Function to get the winning bidder of an auction
    public fun get_winning_bidder(self: &Bid) : (ID, address) {
        (self.auction_id, self.winner)
    }

    // Function to check if an auction has ended
    public fun get_ended_auctions<T: key + store>(self: &Auction<T>) : bool {
        !self.active
    }

    // Function to check if a user is an active bidder in an auction
    public fun get_active_bidders<T: key + store>(self: &Auction<T>, user: address) : bool {
        // Check if the user is a bidder in the auction
        assert!(table::contains(&self.bidders, user), ERROR_NOT_BID);
        true
    }

    // Define a constant for the minimum bid increment
    const MIN_BID_INCREMENT: u64 = 10; // Adjust this value as needed

    // Function to withdraw a bid from an auction
    public fun close_auction<T: key + store>(cap: &AuctionCap, self: Auction<T>, ctx: &mut TxContext) {
        // Validate the auction cap
        assert!(cap.auction_id == object::id(&self), ERROR_INVALID_CAP);
        // Check the auction closed
        assert!(!self.active, ERROR_AUCTION_COMPLETED);
        assert!(self.deposit, ERROR_AUCTION_COMPLETED);

        let Auction {
            id: id_,
            owner: _,
            car_id: _,
            bidders: bidders_,
            starting_price: _,
            highest_bid: _,
            highest_address: buyer,
            start_time: _,
            end_time: _,
            item: item_,
            deposit: _,
            active: _,
        } = self;

        object::delete(id_);
        table::destroy_empty(bidders_);
        transfer::public_transfer(item_, buyer);
    }
}
