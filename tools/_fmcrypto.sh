# Shared crypto parameters for DAHOOM licensing.
# Keep these identical in the builder tools and in the client loader.
FM_CIPHER="-aes-256-cbc -pbkdf2 -iter 200000 -salt"
# Where the plaintext master source lives (private, gitignored, never pushed).
FM_SRC_DIR="src"
# Files inside FM_SRC_DIR that make up the protected payload (the seller's IP).
FM_PAYLOAD=(menu.sh ssh update_panel.sh npvt_edit.py panel/panel.py panel/index.html panel/reseller.html panel/v2ray_manager.py panel/bandwidth_link.py panel/connlog.py)
