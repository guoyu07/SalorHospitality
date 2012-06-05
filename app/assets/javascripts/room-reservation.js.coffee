# document ready code
$ ->
  connect 'salor_hotel.refresh_db', 'ajax.update_resources.success', window.update_salor_hotel_db
  connect 'salor_hotel.refresh_rooms', 'ajax.update_resources.success', window.render_rooms
  if window.openDatabase
    _set 'db', openDatabase('SalorHotel', '1.0', 'salor_hotel_database', 200000)
  # hotel_add_price_form_button()
  hotel_add_room_container()
  initialize_json()


# Updates the local DB from JSON objects delivered by rails. Hooked into update_resources of the main app.
window.update_salor_hotel_db = ->
  db = _get 'db'
  db.transaction (tx) ->
    tx.executeSql 'DROP TABLE IF EXISTS surcharges;'
    tx.executeSql 'DROP TABLE IF EXISTS rooms;'
    tx.executeSql 'DROP TABLE IF EXISTS room_prices;'
    tx.executeSql 'CREATE TABLE surcharges (id INTEGER PRIMARY KEY, name STRING, season_id INTEGER, guest_type_id INTEGER, amount FLOAT, radio_select BOOLEAN);'
    tx.executeSql 'CREATE TABLE rooms (id INTEGER PRIMARY KEY, name STRING, room_type_id INTEGER);'
    tx.executeSql 'CREATE TABLE room_prices (id INTEGER PRIMARY KEY, guest_type_id INTEGER, room_type_id INTEGER, season_id INTEGER, base_price FLOAT);'
    $.each resources.sc, (k,v) ->
      tx.executeSql 'INSERT INTO surcharges (id, name, season_id, guest_type_id, amount, radio_select) VALUES (?,?,?,?,?,?);', [k, v.n, v.sn, v.gt, v.a, v.r]
    $.each resources.r, (k,v) ->
      tx.executeSql 'INSERT INTO rooms (id, name, room_type_id) VALUES (?,?,?);', [k, v.n, v.rt]
    $.each resources.rp, (k,v) ->
      tx.executeSql 'INSERT INTO room_prices (id, guest_type_id, room_type_id, season_id, base_price) VALUES (?,?,?,?,?);', [k, v.gt, v.rt, v.sn, v.p]


# Updates the visual room buttons. Hooked into update_resources of the main app.
window.render_rooms = ->
  $('#rooms').html ''
  $.each resources.r, (k,v) ->
    room = $ document.createElement 'div'
    room.addClass 'room'
    room.html v.n
    room.on 'click', ->
      display_hotel_price_form k
      submit_json.booking.room_id = k
      submit_json.booking.room_type_id = v.rt
    $('#rooms').append room

# Initializes the main attributes of the submit_json object.
initialize_json = ->
  submit_json['booking'] = {}
  submit_json.booking['season_id'] = null
  submit_json.booking['room_id'] = null
  submit_json.booking['room_type_id'] = null
  submit_json['booking_items'] = {}
  items_json['booking'] = {}
  #_set 'reservation_items_json', {}

# Called by document.ready. Serves as a replacement for HTML templates.
hotel_add_room_container = ->
  room_container = $ document.createElement 'div'
  room_container.attr 'id', 'rooms'
  $('#main').append room_container

# Called when clicking on a room. Serves as a replacement for HTML templates.
display_hotel_price_form = ->
  hotel_price_form = create_dom_element 'div', {id:'hotel_price_form'}, '', '#main'
  surcharges_container = create_dom_element 'div', {id:'surcharges'}, '', hotel_price_form
  surcharges_headers = create_dom_element 'div', {id:'surcharges_headers'}, '', surcharges_container
  surcharges_rows_container = create_dom_element 'div', {id:'booking_items'}, '', surcharges_container
  booking_subtotal = create_dom_element 'div', {id:'booking_subtotal'}, '', surcharges_container
  render_season_buttons()
  render_guest_type_buttons()
  render_surcharge_header()


# Called by display_hotel_price_form. Just displays buttons for seasons, adds an onclick function and highlights the current season.
render_season_buttons = ->
  season_container = create_dom_element 'div', {id:'seasons'}, '', '#hotel_price_form'
  $.each resources.sn, (id,v) ->
    sbutton = create_dom_element 'div', {class:'season',id:'season_'+id}, v.n, season_container
    sbutton.on 'click', ->
      change_season(id)
    if v.c == true
      sbutton.addClass 'selected'
      submit_json.booking.season_id = id

change_season = (id) ->
  submit_json.booking.season_id = id
  sbutton = $('#season_' + id)
  $('.season').removeClass 'selected'
  sbutton.addClass 'selected'
  update_json_booking_items()
  setTimeout ->
    render_booking_items_from_json()
  , 150


# This gets unique names of surcharges from the DB. Those names will be rendered as headers for the price calcualtion popup, and will be stored as an array in the jQuery "surcharge_headers" variable. This variable is used later on in the function "render_surcharge_row" to align the corresponding surcharge radio/checkboxes beneath the proper headings. The reason for the alignment is that not all GuestTypes have an identical set of surcharges, so we build a common superset.
render_surcharge_header= ->
  db = _get 'db'
  db.transaction (tx) ->
    tx.executeSql "SELECT DISTINCT name FROM surcharges WHERE guest_type_id IS NOT NULL;", [], (tx,res) ->
      header = create_dom_element 'div', {class:'header'}, 'i18n GuestType', '#surcharges_headers'
      header = create_dom_element 'div', {class:'header'}, 'i18n count', '#surcharges_headers'
      surcharge_headers = []
      for i in [0..res.rows.length-1]
        record = res.rows.item(i)
        surcharge_headers.push record.name
        header = create_dom_element 'div', {class:'header'}, record.name, '#surcharges_headers'
      _set 'surcharge_headers', surcharge_headers



# We can't use the DB results directly to render the input elements, since the headers dictate actually the exact appearance. Not all UserTypes have an identical set of Surcharges. Therefore we build an object called surcharge_guest_object that will be matched later to the surcharge_header object via it's key. We can avoid running several SQL queries with this pre-rendered object.


# Called by display_hotel_price_form. Just displays buttons for guest_types, adds an onclick function.
render_guest_type_buttons = ->
  guest_types_container = $ document.createElement 'div'
  guest_types_container.attr 'id', 'guest_types'
  $('#hotel_price_form').append guest_types_container
  $.each resources.gt, (k,v) ->
    gtbutton = create_dom_element 'div', {class:'guest_type'}, v.n, guest_types_container
    gtbutton.on 'click', ->
      id = add_json_booking_item parseInt(k), v.n
      setTimeout ->
        render_booking_item(id)
      , 30


# This function renders HTML input tags for the selected GuestType beneath the proper headers, as well as an text field for the quantity of the GuestType. The data source is items_json.booking. It also adds the base RoomPrice for the selected GuestType when no Surcharge radio/checkbox tags are selected. If any radio/checkbox Surcharge tags are selected, onclick events will add the Surcharge amount to the base RoomPrice. This function also manages the items_json and submit_json objects so that they can be submitted to the server where they will be saved as a Booking.
add_json_booking_item = (guest_type_id, guest_type_name) ->
  booking_item_id = get_unique_booking_number()
  submit_json.booking_items[booking_item_id] = {count:1, guest_type_id:guest_type_id}
  items_json.booking[booking_item_id] = {guest_type_id:guest_type_id, count:1, base_price:null, surcharges:{}}
  db = _get 'db'
  db.transaction (tx) ->
    tx.executeSql 'SELECT id, name, amount, radio_select FROM surcharges WHERE guest_type_id = ' + guest_type_id + ' AND season_id = ' + submit_json.booking.season_id + ';', [], (tx,res) ->
      for i in [0..res.rows.length-1]
        record = res.rows.item(i)
        items_json.booking[booking_item_id].surcharges[record.name] = {id:record.id,amount:record.amount, radio_select:record.radio_select, selected:false}
  update_base_price booking_item_id
  return booking_item_id

  
update_json_booking_items = ->
  $.each items_json.booking, (k,v) ->
    guest_type_id = items_json.booking[k].guest_type_id
    update_base_price k
    db = _get 'db'
    db.transaction (tx) ->
      tx.executeSql 'SELECT id, name, amount, radio_select FROM surcharges WHERE guest_type_id = ' + guest_type_id + ' AND season_id = ' + submit_json.booking.season_id + ';', [], (tx,res) ->
        for i in [0..res.rows.length-1]
          record = res.rows.item(i)
          items_json.booking[k].surcharges[record.name].id = record.id
          items_json.booking[k].surcharges[record.name].amount = record.amount
          items_json.booking[k].surcharges[record.name].radio_select = record.radio_select

update_base_price = (k) ->
    db = _get 'db'
    db.transaction (tx) ->
      tx.executeSql 'SELECT id, base_price FROM room_prices WHERE room_type_id = ' + submit_json.booking.room_type_id + ' AND guest_type_id = ' + items_json.booking[k].guest_type_id + ' AND season_id = ' + submit_json.booking.season_id + ';', [], (tx,res) ->
        base_price = res.rows.item(0).base_price
        items_json.booking[k].base_price = base_price


render_booking_item = (booking_item_id) ->
  guest_type_id = items_json.booking[booking_item_id].guest_type_id
  guest_type_name = resources.gt[guest_type_id].n
  booking_item_row = create_dom_element 'div', {class:'booking_item', id:'booking_item'+booking_item_id}, '', '#booking_items'
  surcharge_headers = _get 'surcharge_headers'
  create_dom_element 'div', {class:'surcharge_col'}, guest_type_name, booking_item_row
  render_booking_item_count booking_item_id

  for header in surcharge_headers
    if items_json.booking[booking_item_id].surcharges.hasOwnProperty(header)
      surcharge_col = create_dom_element 'div', {class:'surcharge_col surcharge_col_'+booking_item_id}, '', booking_item_row
      if items_json.booking[booking_item_id].surcharges[header].radio_select
        input_tag = create_dom_element 'input', {type:'radio', name:'radio_surcharge_'+booking_item_id, booking_item_id:booking_item_id, surcharge_name:header}, '', surcharge_col
      else
        input_tag = create_dom_element 'input', {type:'checkbox', name:'checkbox_surcharge_'+booking_item_id, booking_item_id:booking_item_id, surcharge_name:header}, '', surcharge_col
      (=>
        h = header
        input_tag.on 'change', ->
          save_selected_input_state this, booking_item_id, h
          update_booking_totals()
        )()
      if items_json.booking[booking_item_id].surcharges[header].selected
        input_tag.attr 'checked', true
  update_booking_totals()


save_selected_input_state = (element, booking_item_id, surcharge_name) ->
  $.each items_json.booking[booking_item_id].surcharges, (k,v) ->
    items_json.booking[booking_item_id].surcharges[k].selected = false
    true
  items_json.booking[booking_item_id].surcharges[surcharge_name].selected = $(element).is(':checked')
    
    


render_booking_items_from_json = ->
  $('#booking_items').html ''
  $.each items_json.booking, (k,v) ->
    render_booking_item k

render_booking_item_count = (booking_item_id) ->
  count_input_col = create_dom_element 'div', {class:'surcharge_col'}, count_input, '#booking_item' + booking_item_id
  count_input = create_dom_element 'input', {type:'text', id:'booking_item_'+booking_item_id+'_count', class:'booking_item_count', value:items_json.booking[booking_item_id].count}, '', count_input_col
  make_keyboardable count_input, '', update_booking_totals, 'num'
  count_input.on 'keyup', ->
    count = $('#booking_item_' + booking_item_id + '_count').val()
    items_json.booking[booking_item_id].count = count
    update_booking_totals()

booking_item_total = (booking_item_id) ->
  total = items_json.booking[booking_item_id].base_price
  $.each items_json.booking[booking_item_id].surcharges, (k,v) ->
    if v.selected == true
      total += v.amount
    true
  count = items_json.booking[booking_item_id].count
  total *= count
  $('#booking_item_' + booking_item_id + '_total').html total
  total


update_booking_totals = ->
  subtotal = 0
  $.each items_json.booking, (k,v) ->
    subtotal += booking_item_total k
    true
  $('#booking_subtotal').html subtotal
  subtotal


make_keyboardable = (element,open_on,accepted,layout) ->
  element.keyboard {
    openOn:open_on
    accepted:accepted
    layout:layout
  }
  element.select()
  element.on 'click', ->
    element.getkeyboard().reveal()


sqlErrorHandler = (e) ->
  alert 'An SQL error occurred.'

create_dom_element = (tag,attrs,content,append_to) ->
  element = $ document.createElement tag
  $.each attrs, (k,v) ->
    element.attr k, v
  element.html content
  if append_to != ''
    $(append_to).append element
  return element

get_unique_booking_number = ->
  number = _get 'unique_surcharge_row_number'
  if typeof(number) == 'undefined'
    number = 1
  else
    number += 1
  _set 'unique_surcharge_row_number', number
  return 'd' + number
