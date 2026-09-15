"""Messaging: who may talk to whom, privacy of threads, unread state and alerts."""

from unittest import mock

from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APITestCase

from apps.messaging.models import Conversation, Message
from apps.notifications import push
from apps.notifications.models import DeviceToken, Notification
from apps.schools.models import School
from apps.students.models import Class, Student

User = get_user_model()


class MessagingFixture(APITestCase):
    def setUp(self):
        self.school = School.objects.create(name='Aaa Message School', code='MSG01')
        self.other_school = School.objects.create(name='Zzz Message Other', code='MSG02')

        def user(username, role, school=None, first_name='', active=True):
            return User.objects.create_user(username=username, password='x', role=role, first_name=first_name,
                                            school=school or self.school, is_active=active)

        self.admin = user('ms_admin', User.Role.ADMIN, first_name='Office')
        self.priya = user('ms_priya', User.Role.TEACHER, first_name='Priya')        # class teacher of 5-A
        self.vikram = user('ms_vikram', User.Role.TEACHER, first_name='Vikram')     # subject teacher in 5-A
        self.anita = user('ms_anita', User.Role.TEACHER, first_name='Anita')        # teaches only 6-B
        self.meena = user('ms_meena', User.Role.PARENT, first_name='Meena')         # Kavya, 5-A
        self.ravi = user('ms_ravi', User.Role.PARENT, first_name='Ravi')            # Nila, 6-B
        self.gone = user('ms_gone', User.Role.PARENT, first_name='Gone', active=False)
        self.outsider = user('ms_outsider', User.Role.TEACHER, school=self.other_school)

        self.class_5a = Class.objects.create(school=self.school, name='Grade 5', section='A',
                                             academic_year='2026-2027', class_teacher=self.priya)
        self.class_5a.teachers.add(self.priya, self.vikram)
        self.class_6b = Class.objects.create(school=self.school, name='Grade 6', section='B',
                                             academic_year='2026-2027', class_teacher=self.anita)
        self.class_6b.teachers.add(self.anita)

        self.kavya = Student.objects.create(school=self.school, admission_number='MS-1', first_name='Kavya',
                                            class_enrolled=self.class_5a)
        self.kavya.parents.add(self.meena, self.gone)
        self.nila = Student.objects.create(school=self.school, admission_number='MS-2', first_name='Nila',
                                           class_enrolled=self.class_6b)
        self.nila.parents.add(self.ravi)

    def start(self, sender, recipient, body='Hello'):
        self.client.force_authenticate(user=sender)
        return self.client.post('/api/v1/messages/conversations/', {'recipient_id': recipient.id, 'body': body},
                                format='json')

    def reply(self, sender, conversation_id, body='Reply'):
        self.client.force_authenticate(user=sender)
        return self.client.post(f'/api/v1/messages/conversations/{conversation_id}/messages/', {'body': body},
                                format='json')


class WhoMayMessageWhomTests(MessagingFixture):
    def test_admin_and_teacher_both_ways(self):
        self.assertEqual(self.start(self.admin, self.priya).status_code, status.HTTP_201_CREATED)
        self.assertEqual(self.start(self.anita, self.admin).status_code, status.HTTP_201_CREATED)

    def test_admin_and_parent_both_ways(self):
        self.assertEqual(self.start(self.admin, self.ravi).status_code, status.HTTP_201_CREATED)
        self.assertEqual(self.start(self.meena, self.admin).status_code, status.HTTP_201_CREATED)

    def test_teacher_messages_parents_of_their_classes_only(self):
        self.assertEqual(self.start(self.priya, self.meena).status_code, status.HTTP_201_CREATED)
        self.assertEqual(self.start(self.vikram, self.meena).status_code, status.HTTP_201_CREATED)
        refused = self.start(self.priya, self.ravi)
        self.assertEqual(refused.status_code, status.HTTP_403_FORBIDDEN)
        self.assertFalse(Conversation.objects.filter(user_low__in=[self.priya, self.ravi],
                                                     user_high__in=[self.priya, self.ravi]).exists())

    def test_parent_starts_only_with_the_class_teacher(self):
        self.assertEqual(self.start(self.meena, self.priya).status_code, status.HTTP_201_CREATED)
        self.assertEqual(self.start(self.meena, self.vikram).status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(self.start(self.meena, self.anita).status_code, status.HTTP_403_FORBIDDEN)

    def test_parent_may_reply_to_a_subject_teacher_who_wrote_first(self):
        conversation_id = self.start(self.vikram, self.meena).data['id']
        self.assertEqual(self.reply(self.meena, conversation_id).status_code, status.HTTP_201_CREATED)

    def test_nobody_else(self):
        cases = [
            (self.meena, self.ravi), (self.priya, self.anita), (self.admin, self.outsider),
            (self.priya, self.gone), (self.admin, self.admin),
        ]
        for sender, recipient in cases:
            self.assertEqual(self.start(sender, recipient).status_code, status.HTTP_403_FORBIDDEN,
                             f'{sender.username} -> {recipient.username}')

    def test_unknown_id_looks_the_same_as_forbidden(self):
        self.client.force_authenticate(user=self.meena)
        res = self.client.post('/api/v1/messages/conversations/', {'recipient_id': 999999, 'body': 'Hi'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_one_conversation_per_pair_whoever_starts(self):
        first = self.start(self.admin, self.meena).data['id']
        second = self.start(self.meena, self.admin).data['id']
        self.assertEqual(first, second)
        self.assertEqual(Conversation.objects.count(), 1)
        self.assertEqual(Message.objects.count(), 2)

    def test_relationship_ending_closes_the_thread(self):
        conversation_id = self.start(self.vikram, self.meena).data['id']
        self.class_5a.teachers.remove(self.vikram)

        self.assertEqual(self.reply(self.vikram, conversation_id).status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(self.reply(self.meena, conversation_id).status_code, status.HTTP_403_FORBIDDEN)
        self.client.force_authenticate(user=self.meena)
        listing = self.client.get('/api/v1/messages/conversations/').data['results']
        self.assertFalse(listing[0]['can_reply'])

    def test_message_body_rules(self):
        self.assertEqual(self.start(self.admin, self.priya, body='   ').status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(self.start(self.admin, self.priya, body='x' * 2001).status_code, status.HTTP_400_BAD_REQUEST)


class PrivacyTests(MessagingFixture):
    def test_outsiders_cannot_read_or_write_a_thread(self):
        conversation_id = self.start(self.priya, self.meena, body='Kavya did well today').data['id']
        for intruder in (self.ravi, self.vikram, self.admin):
            self.client.force_authenticate(user=intruder)
            self.assertEqual(self.client.get(f'/api/v1/messages/conversations/{conversation_id}/').status_code,
                             status.HTTP_404_NOT_FOUND, intruder.username)
            self.assertEqual(self.reply(intruder, conversation_id).status_code, status.HTTP_404_NOT_FOUND)
            listing = self.client.get('/api/v1/messages/conversations/').data['results']
            self.assertNotIn(conversation_id, [row['id'] for row in listing])
        self.assertEqual(Message.objects.count(), 1)


class UnreadAndAlertTests(MessagingFixture):
    def test_unread_counts_and_reading(self):
        conversation_id = self.start(self.priya, self.meena, body='One').data['id']
        self.reply(self.priya, conversation_id, body='Two')

        self.client.force_authenticate(user=self.meena)
        self.assertEqual(self.client.get('/api/v1/messages/unread-count/').data['unread_count'], 2)
        row = self.client.get('/api/v1/messages/conversations/').data['results'][0]
        self.assertEqual((row['unread_count'], row['last_message'], row['other']['full_name']), (2, 'Two', 'Priya'))

        thread = self.client.get(f'/api/v1/messages/conversations/{conversation_id}/').data
        self.assertEqual([m['body'] for m in thread['messages']], ['One', 'Two'])
        self.assertFalse(thread['messages'][0]['is_mine'])
        self.assertEqual(self.client.get('/api/v1/messages/unread-count/').data['unread_count'], 0)

        self.client.force_authenticate(user=self.priya)
        self.assertEqual(self.client.get('/api/v1/messages/unread-count/').data['unread_count'], 0)

    def test_one_alert_until_read_then_alert_again(self):
        conversation_id = self.start(self.priya, self.meena, body='First').data['id']
        self.reply(self.priya, conversation_id, body='Second')
        self.reply(self.priya, conversation_id, body='Third')
        alerts = Notification.objects.filter(recipient=self.meena, notification_type='MESSAGE')
        self.assertEqual(alerts.count(), 1)
        self.assertEqual(alerts.get().title, 'Message from Priya')

        self.client.force_authenticate(user=self.meena)
        self.client.get(f'/api/v1/messages/conversations/{conversation_id}/')
        self.assertFalse(alerts.filter(is_read=False).exists())

        self.reply(self.priya, conversation_id, body='Fourth')
        self.assertEqual(alerts.count(), 2)
        self.assertFalse(Notification.objects.filter(recipient=self.gone).exists())

    def test_alert_is_pushed_to_the_recipients_phone(self):
        DeviceToken.objects.create(user=self.meena, token='meena-phone-token-000000', platform='ANDROID')
        with mock.patch.object(push, 'send_to_tokens',
                               return_value={'sent': 1, 'failed': 0, 'invalid_tokens': [], 'auth_failed': False}) as send:
            conversation_id = self.start(self.priya, self.meena).data['id']
        self.assertEqual(send.call_count, 1)
        self.assertEqual(send.call_args.kwargs['data']['conversation_id'], conversation_id)

    def test_older_messages_page_backwards(self):
        conversation_id = self.start(self.admin, self.priya, body='m0').data['id']
        for i in range(1, 60):
            self.reply(self.admin, conversation_id, body=f'm{i}')
        self.client.force_authenticate(user=self.priya)
        latest = self.client.get(f'/api/v1/messages/conversations/{conversation_id}/').data
        self.assertEqual(len(latest['messages']), 50)
        self.assertTrue(latest['has_older'])
        self.assertEqual(latest['messages'][-1]['body'], 'm59')
        older = self.client.get(
            f"/api/v1/messages/conversations/{conversation_id}/?before={latest['messages'][0]['id']}").data
        self.assertEqual([m['body'] for m in older['messages']], [f'm{i}' for i in range(10)])
        self.assertFalse(older['has_older'])


class ContactsTests(MessagingFixture):
    def names(self, user, search=''):
        self.client.force_authenticate(user=user)
        return {row['full_name'] for row in self.client.get(f'/api/v1/messages/contacts/?search={search}').data}

    def test_admin_contacts_are_teachers_and_parents(self):
        self.assertEqual(self.names(self.admin), {'Priya', 'Vikram', 'Anita', 'Meena', 'Ravi'})

    def test_teacher_contacts_are_the_office_and_their_parents(self):
        self.assertEqual(self.names(self.priya), {'Office', 'Meena'})
        self.assertEqual(self.names(self.anita), {'Office', 'Ravi'})

    def test_parent_contacts_are_the_office_and_class_teachers(self):
        self.assertEqual(self.names(self.meena), {'Office', 'Priya'})

    def test_teacher_finds_a_parent_by_the_childs_name(self):
        self.assertEqual(self.names(self.priya, 'Kavya'), {'Meena'})

    def test_contact_context_explains_the_relationship(self):
        self.client.force_authenticate(user=self.priya)
        rows = {row['full_name']: row['context'] for row in self.client.get('/api/v1/messages/contacts/').data}
        self.assertEqual(rows['Meena'], 'Parent of Kavya (Grade 5 - A)')
        self.client.force_authenticate(user=self.meena)
        rows = {row['full_name']: row['context'] for row in self.client.get('/api/v1/messages/contacts/').data}
        self.assertEqual(rows['Priya'], 'Class teacher, Grade 5 - A')
