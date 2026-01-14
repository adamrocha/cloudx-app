package main

import (
	"encoding/json"
	"log"
	"math/rand"
	"net/http"
	"os"
	"strings"

	"github.com/google/uuid"
)

func RunBidder(port string) {
	mux := http.NewServeMux()
	srv := NewBidder()
	srv.Mount(mux)

	bindaddr := ":" + port
	log.Printf("CloudX Mock Bidder starting on %s...", bindaddr)

	// Default serve mux is used by pprof
	http.Handle("/", mux)

	server := &http.Server{
		Addr:    bindaddr,
		Handler: http.DefaultServeMux,
	}

	if err := server.ListenAndServe(); err != nil {
		log.Fatalf("Server failed: %s", err)
	}
	os.Exit(0)
}

func NewBidder() *Bidder {
	return &Bidder{}
}

type Bidder struct{}

func (b *Bidder) Mount(mux *http.ServeMux) {
	mux.HandleFunc("POST /bid", b.Bid)
}

func (b *Bidder) Bid(w http.ResponseWriter, r *http.Request) {
	var ar AuctionRequest
	defer r.Body.Close()
	if err := json.NewDecoder(r.Body).Decode(&ar); err != nil {
		http.Error(w, "invalid request", http.StatusBadRequest)
		return
	}

	// Bidders don't bid on every opportunity
	if !shouldBid(&ar) {
		w.WriteHeader(http.StatusNoContent)
		return
	}

	bid := BidResponse{
		AuctionID: ar.ID,
		BidID:     "bid_" + uuid.NewString(),
		Price:     randomPriceBetween(1, 10),
		// Bidders sometimes return some extra data with their response. Here
		// it's ~10MB of nonsense, just to simulate an adversarial case.
		Ext: `{"payload": "` + strings.Repeat("x", 1024*1024*10) + `"}`,
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(bid); err != nil {
		panic(err)
	}
}

func shouldBid(_ *AuctionRequest) bool {
	return rand.Intn(100) < 85
}

func randomPriceBetween(bottom, top float64) float64 {
	return bottom + rand.Float64()*(top-bottom)
}
