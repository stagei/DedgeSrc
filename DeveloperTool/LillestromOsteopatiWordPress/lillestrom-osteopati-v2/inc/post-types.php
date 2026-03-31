<?php
/**
 * Custom Post Types for Lillestrøm Osteopati theme.
 *
 * Registers the "behandler" (Staff/Practitioners) and "faq_item" (FAQ)
 * custom post types, along with meta boxes for practitioner details.
 *
 * @package Lillestrom_Osteopati
 * @since   1.0.0
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit; // Prevent direct access.
}

/* --------------------------------------------------------------------------
 * 1. Register Custom Post Types
 * ----------------------------------------------------------------------- */

add_action( 'init', 'lo_register_post_types' );

/**
 * Register the Behandler and FAQ custom post types.
 *
 * @return void
 */
function lo_register_post_types() {

	/* ---- Behandler (Staff / Practitioners) ---- */

	$behandler_labels = array(
		'name'                  => _x( 'Behandlere', 'Post type general name', 'lillestrom-osteopati-v2' ),
		'singular_name'         => _x( 'Behandler', 'Post type singular name', 'lillestrom-osteopati-v2' ),
		'menu_name'             => _x( 'Behandlere', 'Admin menu text', 'lillestrom-osteopati-v2' ),
		'name_admin_bar'        => _x( 'Behandler', 'Add New on Toolbar', 'lillestrom-osteopati-v2' ),
		'add_new'               => __( 'Legg til ny', 'lillestrom-osteopati-v2' ),
		'add_new_item'          => __( 'Legg til ny behandler', 'lillestrom-osteopati-v2' ),
		'new_item'              => __( 'Ny behandler', 'lillestrom-osteopati-v2' ),
		'edit_item'             => __( 'Rediger behandler', 'lillestrom-osteopati-v2' ),
		'view_item'             => __( 'Vis behandler', 'lillestrom-osteopati-v2' ),
		'all_items'             => __( 'Alle behandlere', 'lillestrom-osteopati-v2' ),
		'search_items'          => __( 'Søk i behandlere', 'lillestrom-osteopati-v2' ),
		'not_found'             => __( 'Ingen behandlere funnet.', 'lillestrom-osteopati-v2' ),
		'not_found_in_trash'    => __( 'Ingen behandlere funnet i papirkurven.', 'lillestrom-osteopati-v2' ),
		'archives'              => __( 'Behandlerarkiv', 'lillestrom-osteopati-v2' ),
		'filter_items_list'     => __( 'Filtrer behandlerliste', 'lillestrom-osteopati-v2' ),
		'items_list_navigation' => __( 'Behandlerlistenavigering', 'lillestrom-osteopati-v2' ),
		'items_list'            => __( 'Behandlerliste', 'lillestrom-osteopati-v2' ),
	);

	$behandler_args = array(
		'labels'             => $behandler_labels,
		'public'             => true,
		'has_archive'        => false,
		'show_in_rest'       => true,
		'supports'           => array( 'title', 'editor', 'thumbnail', 'page-attributes' ),
		'menu_icon'          => 'dashicons-businessperson',
		'rewrite'            => array( 'slug' => 'behandler' ),
		'capability_type'    => 'post',
		'menu_position'      => 20,
		'show_in_menu'       => true,
		'show_ui'            => true,
		'show_in_admin_bar'  => true,
		'show_in_nav_menus'  => true,
		'can_export'         => true,
		'exclude_from_search'=> false,
		'publicly_queryable' => true,
	);

	register_post_type( 'behandler', $behandler_args );

	/* ---- FAQ Item ---- */

	$faq_labels = array(
		'name'                  => _x( 'FAQ', 'Post type general name', 'lillestrom-osteopati-v2' ),
		'singular_name'         => _x( 'FAQ', 'Post type singular name', 'lillestrom-osteopati-v2' ),
		'menu_name'             => _x( 'FAQ', 'Admin menu text', 'lillestrom-osteopati-v2' ),
		'name_admin_bar'        => _x( 'FAQ', 'Add New on Toolbar', 'lillestrom-osteopati-v2' ),
		'add_new'               => __( 'Legg til ny', 'lillestrom-osteopati-v2' ),
		'add_new_item'          => __( 'Legg til nytt spørsmål', 'lillestrom-osteopati-v2' ),
		'new_item'              => __( 'Nytt spørsmål', 'lillestrom-osteopati-v2' ),
		'edit_item'             => __( 'Rediger spørsmål', 'lillestrom-osteopati-v2' ),
		'view_item'             => __( 'Vis spørsmål', 'lillestrom-osteopati-v2' ),
		'all_items'             => __( 'Alle spørsmål', 'lillestrom-osteopati-v2' ),
		'search_items'          => __( 'Søk i spørsmål', 'lillestrom-osteopati-v2' ),
		'not_found'             => __( 'Ingen spørsmål funnet.', 'lillestrom-osteopati-v2' ),
		'not_found_in_trash'    => __( 'Ingen spørsmål funnet i papirkurven.', 'lillestrom-osteopati-v2' ),
		'archives'              => __( 'FAQ-arkiv', 'lillestrom-osteopati-v2' ),
		'filter_items_list'     => __( 'Filtrer FAQ-liste', 'lillestrom-osteopati-v2' ),
		'items_list_navigation' => __( 'FAQ-listenavigering', 'lillestrom-osteopati-v2' ),
		'items_list'            => __( 'FAQ-liste', 'lillestrom-osteopati-v2' ),
	);

	$faq_args = array(
		'labels'             => $faq_labels,
		'public'             => true,
		'has_archive'        => false,
		'show_in_rest'       => true,
		'supports'           => array( 'title', 'editor', 'page-attributes' ),
		'menu_icon'          => 'dashicons-editor-help',
		'rewrite'            => array( 'slug' => 'faq' ),
		'capability_type'    => 'post',
		'menu_position'      => 21,
		'show_in_menu'       => true,
		'show_ui'            => true,
		'show_in_admin_bar'  => true,
		'show_in_nav_menus'  => true,
		'can_export'         => true,
		'exclude_from_search'=> false,
		'publicly_queryable' => true,
	);

	register_post_type( 'faq_item', $faq_args );

	/* ---- Behandling Type (Treatment Cards) ---- */

	register_post_type( 'behandling_type', array(
		'labels'             => array(
			'name'          => _x( 'Behandlinger', 'Post type general name', 'lillestrom-osteopati-v2' ),
			'singular_name' => _x( 'Behandling', 'Post type singular name', 'lillestrom-osteopati-v2' ),
			'menu_name'     => _x( 'Behandlinger', 'Admin menu text', 'lillestrom-osteopati-v2' ),
			'add_new'       => __( 'Legg til ny', 'lillestrom-osteopati-v2' ),
			'add_new_item'  => __( 'Legg til ny behandling', 'lillestrom-osteopati-v2' ),
			'edit_item'     => __( 'Rediger behandling', 'lillestrom-osteopati-v2' ),
			'all_items'     => __( 'Alle behandlinger', 'lillestrom-osteopati-v2' ),
			'not_found'     => __( 'Ingen behandlinger funnet.', 'lillestrom-osteopati-v2' ),
		),
		'public'             => true,
		'has_archive'        => false,
		'show_in_rest'       => true,
		'supports'           => array( 'title', 'editor', 'page-attributes' ),
		'menu_icon'          => 'dashicons-heart',
		'rewrite'            => array( 'slug' => 'behandling-type' ),
		'capability_type'    => 'post',
		'menu_position'      => 22,
	) );
}

/* --------------------------------------------------------------------------
 * Behandling Type Meta Box (Icon)
 * ----------------------------------------------------------------------- */

add_action( 'add_meta_boxes', 'lo_add_behandling_type_meta_boxes' );

function lo_add_behandling_type_meta_boxes() {
	add_meta_box(
		'lo_behandling_icon',
		__( 'Ikon (Font Awesome)', 'lillestrom-osteopati-v2' ),
		'lo_render_behandling_icon_meta_box',
		'behandling_type',
		'side',
		'default'
	);
}

function lo_render_behandling_icon_meta_box( $post ) {
	wp_nonce_field( 'lo_save_behandling_icon', 'lo_behandling_icon_nonce' );
	$icon = get_post_meta( $post->ID, '_behandling_icon', true );
	$choices = function_exists( 'lo_get_icon_choices' ) ? lo_get_icon_choices() : array();
	?>
	<p>
		<select id="lo_behandling_icon" name="_behandling_icon" class="large-text" style="width:100%">
			<?php foreach ( $choices as $value => $label ) : ?>
				<option value="<?php echo esc_attr( $value ); ?>" <?php selected( $icon, $value ); ?>>
					<?php echo esc_html( $label ); ?>
				</option>
			<?php endforeach; ?>
		</select>
	</p>
	<p class="description">
		<?php esc_html_e( 'Velg ikonet som vises på behandlingskortet.', 'lillestrom-osteopati-v2' ); ?>
	</p>
	<?php
}

add_action( 'save_post_behandling_type', 'lo_save_behandling_icon_meta', 10, 2 );

function lo_save_behandling_icon_meta( $post_id, $post ) {
	if ( ! isset( $_POST['lo_behandling_icon_nonce'] ) || ! wp_verify_nonce( $_POST['lo_behandling_icon_nonce'], 'lo_save_behandling_icon' ) ) {
		return;
	}
	if ( defined( 'DOING_AUTOSAVE' ) && DOING_AUTOSAVE ) {
		return;
	}
	if ( ! current_user_can( 'edit_post', $post_id ) ) {
		return;
	}
	if ( isset( $_POST['_behandling_icon'] ) ) {
		update_post_meta( $post_id, '_behandling_icon', sanitize_text_field( wp_unslash( $_POST['_behandling_icon'] ) ) );
	}
}


/* --------------------------------------------------------------------------
 * 2. Behandler Meta Box
 * ----------------------------------------------------------------------- */

add_action( 'add_meta_boxes', 'lo_add_behandler_meta_boxes' );

/**
 * Register the "Behandler-detaljer" meta box on the behandler edit screen.
 *
 * @return void
 */
function lo_add_behandler_meta_boxes() {
	add_meta_box(
		'lo_behandler_details',
		__( 'Behandler-detaljer', 'lillestrom-osteopati-v2' ),
		'lo_render_behandler_meta_box',
		'behandler',
		'normal',
		'high'
	);
}

/**
 * Render the Behandler meta box fields.
 *
 * @param WP_Post $post The current post object.
 * @return void
 */
function lo_render_behandler_meta_box( $post ) {

	// Output a nonce field for verification on save.
	wp_nonce_field( 'lo_save_behandler_meta', 'lo_behandler_meta_nonce' );

	// Retrieve existing meta values (empty string as default).
	$title       = get_post_meta( $post->ID, '_behandler_title', true );
	$education   = get_post_meta( $post->ID, '_behandler_education', true );
	$specialties = get_post_meta( $post->ID, '_behandler_specialties', true );

	?>
	<table class="form-table" role="presentation">

		<!-- Professional title -->
		<tr>
			<th scope="row">
				<label for="lo_behandler_title">
					<?php esc_html_e( 'Tittel', 'lillestrom-osteopati-v2' ); ?>
				</label>
			</th>
			<td>
				<input
					type="text"
					id="lo_behandler_title"
					name="_behandler_title"
					value="<?php echo esc_attr( $title ); ?>"
					class="large-text"
					placeholder="<?php esc_attr_e( 'F.eks. Osteopat D.O. MNOF & Fysioterapeut', 'lillestrom-osteopati-v2' ); ?>"
				/>
				<p class="description">
					<?php esc_html_e( 'Profesjonell tittel som vises under navnet.', 'lillestrom-osteopati-v2' ); ?>
				</p>
			</td>
		</tr>

		<!-- Education -->
		<tr>
			<th scope="row">
				<label for="lo_behandler_education">
					<?php esc_html_e( 'Utdanning', 'lillestrom-osteopati-v2' ); ?>
				</label>
			</th>
			<td>
				<textarea
					id="lo_behandler_education"
					name="_behandler_education"
					rows="5"
					class="large-text"
					placeholder="<?php esc_attr_e( 'Én utdanning per linje', 'lillestrom-osteopati-v2' ); ?>"
				><?php echo esc_textarea( $education ); ?></textarea>
				<p class="description">
					<?php esc_html_e( 'Skriv inn én utdanning per linje.', 'lillestrom-osteopati-v2' ); ?>
				</p>
			</td>
		</tr>

		<!-- Specialties -->
		<tr>
			<th scope="row">
				<label for="lo_behandler_specialties">
					<?php esc_html_e( 'Spesialområder', 'lillestrom-osteopati-v2' ); ?>
				</label>
			</th>
			<td>
				<textarea
					id="lo_behandler_specialties"
					name="_behandler_specialties"
					rows="5"
					class="large-text"
					placeholder="<?php esc_attr_e( 'Ett spesialområde per linje', 'lillestrom-osteopati-v2' ); ?>"
				><?php echo esc_textarea( $specialties ); ?></textarea>
				<p class="description">
					<?php esc_html_e( 'Skriv inn ett spesialområde per linje.', 'lillestrom-osteopati-v2' ); ?>
				</p>
			</td>
		</tr>

	</table>
	<?php
}


/* --------------------------------------------------------------------------
 * 3. Save Behandler Meta
 * ----------------------------------------------------------------------- */

add_action( 'save_post_behandler', 'lo_save_behandler_meta', 10, 2 );

/**
 * Persist the custom meta fields when a Behandler post is saved.
 *
 * Includes nonce verification, autosave check, and capability check.
 *
 * @param int     $post_id The post ID.
 * @param WP_Post $post    The post object.
 * @return void
 */
function lo_save_behandler_meta( $post_id, $post ) {

	// 1. Verify the nonce.
	if (
		! isset( $_POST['lo_behandler_meta_nonce'] ) ||
		! wp_verify_nonce( $_POST['lo_behandler_meta_nonce'], 'lo_save_behandler_meta' )
	) {
		return;
	}

	// 2. Bail on autosave — meta box fields are not submitted.
	if ( defined( 'DOING_AUTOSAVE' ) && DOING_AUTOSAVE ) {
		return;
	}

	// 3. Check that the current user has permission to edit the post.
	if ( ! current_user_can( 'edit_post', $post_id ) ) {
		return;
	}

	// 4. Define the fields to save and their sanitisation callbacks.
	$fields = array(
		'_behandler_title'       => 'sanitize_text_field',
		'_behandler_education'   => 'sanitize_textarea_field',
		'_behandler_specialties' => 'sanitize_textarea_field',
	);

	foreach ( $fields as $meta_key => $sanitize_callback ) {
		if ( isset( $_POST[ $meta_key ] ) ) {
			$clean_value = call_user_func( $sanitize_callback, wp_unslash( $_POST[ $meta_key ] ) );
			update_post_meta( $post_id, $meta_key, $clean_value );
		} else {
			delete_post_meta( $post_id, $meta_key );
		}
	}
}
