package main

import (
	"fmt"
	_ "net/http/pprof" // adds /debug/pprof to any running http server
	"os"
)

type AuctionRequest struct {
	ID    string `json:"id"`
	AppID string `json:"app_id"`
}

type AuctionResult struct {
	AuctionID  string      `json:"auction_id"`
	WinningBid *WinningBid `json:"winning_bid,omitempty"`
}

type WinningBid struct {
	BidID string  `json:"bid_id"`
	Price float64 `json:"price"`
}

type BidRequest struct {
	AppID     string `json:"app_id"`
	AuctionID string `json:"auction_id"`
	BidID     string `json:"bid_id"`
	SSP       string `json:"ssp"`
}

type BidResponse struct {
	AuctionID string  `json:"auction_id"`
	BidID     string  `json:"bid_id"`
	Ext       string  `json:"ext"`
	Price     float64 `json:"price"`
}

func main() {
	args := os.Args[1:]
	if len(args) >= 2 {
		service := args[0]
		port := args[1]
		switch service {
		case "ssp":
			bidderURL := args[2]
			RunSSP(port, bidderURL)
		case "bidder":
			RunBidder(port)
		}
	}
	fmt.Println("usage:")
	fmt.Println("    ./server ssp [port] [bidderURL]")
	fmt.Println("    ./server bidder [port]")
	fmt.Println("")
	fmt.Println("example:")
	fmt.Println("    ./server ssp 8091 http://localhost:8092/bid")
	fmt.Println("    ./server bidder 8092")
	fmt.Println("")
	os.Exit(1)
}
