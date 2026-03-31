<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

$process_label = op_get_option( 'op_process_label', 'How We Work' );
$process_title = op_get_option( 'op_process_title', 'Your First Consultation' );

$op_step_defaults = array(
    1 => array( 'title' => 'Consultation', 'text' => 'We start with a thorough review of your medical history, current complaints and what you need help with.' ),
    2 => array( 'title' => 'Assessment',   'text' => 'A systematic examination to find the root cause of your complaints — not just the symptoms.' ),
    3 => array( 'title' => 'Treatment',    'text' => 'Gentle and effective manual treatment tailored to your needs, using techniques such as mobilisation, manipulation and soft tissue work.' ),
    4 => array( 'title' => 'Follow-up',    'text' => 'You receive advice on exercises and self-care, along with a plan for further treatment if needed.' ),
);

// Build steps: only render if title is non-empty
$steps = array();
$step_num = 1;
for ( $i = 1; $i <= 4; $i++ ) {
    $title = op_get_option( 'op_process_step' . $i . '_title', $op_step_defaults[ $i ]['title'] );
    if ( ! empty( trim( $title ) ) ) {
        $steps[] = array(
            'number' => $step_num,
            'title'  => $title,
            'text'   => op_get_option( 'op_process_step' . $i . '_text', $op_step_defaults[ $i ]['text'] ),
        );
        $step_num++;
    }
}
?>

<?php if ( ! empty( $steps ) ) : ?>
<section class="section section-dark">
    <div class="container">
        <div class="section-header">
            <?php if ( ! empty( trim( $process_label ) ) ) : ?>
                <p class="section-label light"><?php echo esc_html( $process_label ); ?></p>
            <?php endif; ?>
            <?php if ( ! empty( trim( $process_title ) ) ) : ?>
                <h2 class="section-title light"><?php echo esc_html( $process_title ); ?></h2>
            <?php endif; ?>
        </div>
        <div class="process-grid">
            <?php foreach ( $steps as $step ) : ?>
                <div class="process-step">
                    <div class="process-number"><?php echo esc_html( $step['number'] ); ?></div>
                    <h4><?php echo esc_html( $step['title'] ); ?></h4>
                    <?php if ( ! empty( trim( $step['text'] ) ) ) : ?>
                        <p><?php echo esc_html( $step['text'] ); ?></p>
                    <?php endif; ?>
                </div>
            <?php endforeach; ?>
        </div>
    </div>
</section>
<?php endif; ?>
