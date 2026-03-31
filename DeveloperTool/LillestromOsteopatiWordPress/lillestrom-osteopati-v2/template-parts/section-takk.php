<?php if (!defined('ABSPATH')) exit; ?>

<section class="section section-takk" id="takk">
    <div class="container">
        <div class="takk-content">
            <div class="takk-icon"><i class="fas fa-check-circle"></i></div>
            <h2><?php echo esc_html( lo_get_option( 'lo_takk_heading', 'Takk for din henvendelse!' ) ); ?></h2>
            <p><?php echo esc_html( lo_get_option( 'lo_takk_text', 'Vi har mottatt meldingen din og vil svare deg så snart som mulig — vanligvis innen en virkedag.' ) ); ?></p>
            <a href="#hjem" class="btn btn-primary"><?php echo esc_html( lo_get_option( 'lo_takk_button', 'Tilbake til forsiden' ) ); ?></a>
        </div>
    </div>
</section>
